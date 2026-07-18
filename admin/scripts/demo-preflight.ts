#!/usr/bin/env -S pnpm exec tsx

import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { applicationDefault, deleteApp, getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type UserRecord } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const PROJECT_ID = "lumi-ninc-au";
const DEMO_SCHOOL_ID = "lumi_demo_primary_school";
const PORTAL_ORIGIN = "https://lumi-school-admin-au.web.app";
const REPO_ROOT = resolve(import.meta.dirname, "../..");

type DemoRole = "admin" | "teacher" | "parent";

interface SharedAccount {
  role: DemoRole;
  email: string;
  collection: "users" | "parents";
  expectedProfileRole: "schoolAdmin" | "teacher" | "parent";
}

interface SignedInAccount extends SharedAccount {
  uid: string;
  idToken: string;
  userRecord: UserRecord;
}

function fail(message: string): never {
  throw new Error(message);
}

function check(condition: unknown, message: string): asserts condition {
  if (!condition) fail(message);
}

function pass(label: string): void {
  console.log(`  PASS  ${label}`);
}

function sydneyDayKey(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Australia/Sydney",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

function exactObject(actual: Record<string, unknown>, expected: Record<string, unknown>): boolean {
  const actualKeys = Object.keys(actual).sort();
  const expectedKeys = Object.keys(expected).sort();
  return (
    JSON.stringify(actualKeys) === JSON.stringify(expectedKeys) &&
    expectedKeys.every((key) => actual[key] === expected[key])
  );
}

function plistValue(key: string): string {
  return execFileSync(
    "plutil",
    ["-extract", key, "raw", resolve(REPO_ROOT, "ios/Runner/GoogleService-Info.plist")],
    { encoding: "utf8" },
  ).trim();
}

async function signInWithPassword(
  email: string,
  password: string,
  apiKey: string,
  bundleId: string,
): Promise<{ uid: string; idToken: string }> {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-ios-bundle-identifier": bundleId,
      },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  if (!response.ok) {
    fail(`Fresh password sign-in failed for the ${email.includes(".parent") ? "parent" : email.includes(".teacher") ? "teacher" : "administrator"} demo identity (HTTP ${response.status}). Re-provision today's credentials and retry.`);
  }
  const body = (await response.json()) as { localId?: unknown; idToken?: unknown };
  check(typeof body.localId === "string" && body.localId.length > 0, "Identity Toolkit omitted the user id.");
  check(typeof body.idToken === "string" && body.idToken.length > 0, "Identity Toolkit omitted the ID token.");
  return { uid: body.localId, idToken: body.idToken };
}

function firestoreUrl(path: string, apiKey: string): string {
  const encodedPath = path
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents/${encodedPath}?key=${encodeURIComponent(apiKey)}`;
}

function clientHeaders(idToken: string, bundleId: string): Record<string, string> {
  return {
    authorization: `Bearer ${idToken}`,
    "content-type": "application/json",
    "x-ios-bundle-identifier": bundleId,
  };
}

async function clientGet(
  path: string,
  account: SignedInAccount,
  apiKey: string,
  bundleId: string,
): Promise<void> {
  const response = await fetch(firestoreUrl(path, apiKey), {
    headers: clientHeaders(account.idToken, bundleId),
  });
  check(response.status === 200, `${account.role} could not read ${path} through production Rules (HTTP ${response.status}).`);
}

async function clientCommit(
  account: SignedInAccount,
  apiKey: string,
  bundleId: string,
  writes: unknown[],
): Promise<number> {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: clientHeaders(account.idToken, bundleId),
      body: JSON.stringify({ writes }),
    },
  );
  return response.status;
}

function documentName(path: string): string {
  return `projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
}

function updateWrite(path: string, fields: Record<string, unknown>, mask: string[], transforms: unknown[] = []): unknown {
  return {
    update: { name: documentName(path), fields },
    updateMask: { fieldPaths: mask },
    ...(transforms.length > 0 ? { updateTransforms: transforms } : {}),
    currentDocument: { exists: true },
  };
}

async function verifyPortalSession(admin: SignedInAccount): Promise<void> {
  const sessionResponse = await fetch(`${PORTAL_ORIGIN}/api/auth/session`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ idToken: admin.idToken }),
    redirect: "manual",
  });
  check(sessionResponse.status === 200, `Demo administrator portal session failed (HTTP ${sessionResponse.status}).`);
  const cookieHeader = sessionResponse.headers.get("set-cookie");
  check(cookieHeader, "Portal session did not return its HttpOnly session cookie.");
  const cookie = cookieHeader.split(";", 1)[0];

  const meResponse = await fetch(`${PORTAL_ORIGIN}/api/auth/me`, {
    headers: { cookie },
    redirect: "manual",
  });
  check(meResponse.status === 200, `Demo administrator portal read failed (HTTP ${meResponse.status}).`);

  // Empty PATCH is intentionally harmless. A mutable session would return 400
  // after parsing the empty body; the read-only demo session must be rejected
  // at the authentication boundary before any mutation code runs.
  const mutationResponse = await fetch(`${PORTAL_ORIGIN}/api/profile`, {
    method: "PATCH",
    headers: { cookie, "content-type": "application/json" },
    body: "{}",
    redirect: "manual",
  });
  check(mutationResponse.status === 401, `Demo administrator was not rejected by a mutable portal route (HTTP ${mutationResponse.status}).`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const projectArg = args.find((arg) => arg.startsWith("--project="));
  const projectId = projectArg?.slice("--project=".length) ?? "";
  const canary = args.includes("--canary");
  const known = args.every(
    (arg) => arg === "--" || arg === "--canary" || arg.startsWith("--project="),
  );
  if (!known || projectId !== PROJECT_ID) {
    fail(`Usage: pnpm demo:preflight -- --project=${PROJECT_ID} [--canary]`);
  }

  if (getApps().length === 0) {
    initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID });
  }
  const auth = getAuth();
  const db = getFirestore();
  const apiKey = plistValue("API_KEY");
  const bundleId = plistValue("BUNDLE_ID");
  const today = sydneyDayKey();

  console.log(`Lumi demo preflight — ${today} Sydney`);
  console.log("No credential, token, UID, child name, or document ID is printed.\n");

  const [schoolSnap, configSnap, stateSnap, reseedSnap] = await Promise.all([
    db.doc(`schools/${DEMO_SCHOOL_ID}`).get(),
    db.doc("platformConfig/demoAccess").get(),
    db.doc("demoAccess/state").get(),
    db.doc("demoAccess/reseedStatus").get(),
  ]);
  check(schoolSnap.exists && schoolSnap.data()?.isDemo === true, "Configured demo school is missing or not marked isDemo:true.");
  check(configSnap.exists, "platformConfig/demoAccess is missing.");
  check(stateSnap.exists, "No demo password has been provisioned.");
  check(reseedSnap.exists && reseedSnap.data()?.state === "succeeded", "The most recent demo reseed did not finish successfully.");
  check(reseedSnap.data()?.schoolId === DEMO_SCHOOL_ID, "The reseed status points at the wrong school.");
  pass("immutable demo tenant and completed reseed");

  const config = configSnap.data() ?? {};
  const state = stateSnap.data() ?? {};
  const accounts: SharedAccount[] = [
    { role: "admin", email: config.adminEmail, collection: "users", expectedProfileRole: "schoolAdmin" },
    { role: "teacher", email: config.teacherEmail, collection: "users", expectedProfileRole: "teacher" },
    { role: "parent", email: config.parentEmail, collection: "parents", expectedProfileRole: "parent" },
  ];
  check(config.schoolId === DEMO_SCHOOL_ID, "Demo access config points at the wrong school.");
  check(accounts.every((account) => typeof account.email === "string" && account.email.endsWith("@lumi-reading.com")), "Shared demo identities are missing or outside the controlled Lumi mailbox.");
  check(state.dayKey === today && state.scrambledAt == null, `Today's demo access is not active. Provision today's password in the super-admin portal, then rerun this check.`);
  check(typeof state.password === "string" && state.password.length >= 12, "Today's demo credential is missing or malformed.");
  pass("today's rolling credential is active and unscrambled");

  const [studentCount, logCount, classCount, bookCount, allocationCount] = await Promise.all([
    db.collection(`schools/${DEMO_SCHOOL_ID}/students`).count().get(),
    db.collection(`schools/${DEMO_SCHOOL_ID}/readingLogs`).count().get(),
    db.collection(`schools/${DEMO_SCHOOL_ID}/classes`).count().get(),
    db.collection(`schools/${DEMO_SCHOOL_ID}/books`).count().get(),
    db.collection(`schools/${DEMO_SCHOOL_ID}/allocations`).count().get(),
  ]);
  check(studentCount.data().count >= 16, "Demo school has fewer than 16 students.");
  check(logCount.data().count >= 450, "Demo school has fewer than 450 reading logs.");
  check(classCount.data().count >= 2, "Demo school has fewer than two classes.");
  check(bookCount.data().count >= 3, "Demo school has fewer than three school-local books.");
  check(allocationCount.data().count >= 2, "Demo school has fewer than two allocations.");
  pass("customer-facing demo content is populated");

  const signedIn: SignedInAccount[] = [];
  for (const account of accounts) {
    const userRecord = await auth.getUserByEmail(account.email);
    check(!userRecord.disabled && userRecord.emailVerified, `${account.role} Auth identity is disabled or unverified.`);
    check((userRecord.multiFactor?.enrolledFactors ?? []).length === 0, `${account.role} demo identity unexpectedly requires MFA.`);
    const expectedClaims: Record<string, unknown> = {
      demoAccount: true,
      demoSchoolId: DEMO_SCHOOL_ID,
      schoolId: DEMO_SCHOOL_ID,
      ...(account.role === "admin" ? { demoAdminMfaExempt: true, demoReadOnly: true } : {}),
    };
    check(exactObject(userRecord.customClaims ?? {}, expectedClaims), `${account.role} custom claims drifted from the exact allowlist.`);

    const profileRef = db.doc(`schools/${DEMO_SCHOOL_ID}/${account.collection}/${userRecord.uid}`);
    const profileSnap = await profileRef.get();
    const profile = profileSnap.data() ?? {};
    check(profileSnap.exists && profile.role === account.expectedProfileRole && profile.schoolId === DEMO_SCHOOL_ID && profile.isActive !== false, `${account.role} profile is missing, inactive, or has the wrong role/school.`);
    if (account.role === "teacher") check(Array.isArray(profile.classIds) && profile.classIds.length > 0, "Demo teacher has no assigned class.");
    if (account.role === "parent") check(Array.isArray(profile.linkedChildren) && profile.linkedChildren.length >= 2, "Demo parent is not linked to both showcase children.");

    const emailHash = createHash("sha256").update(account.email.toLowerCase().trim()).digest("hex");
    const index = (await db.doc(`userSchoolIndex/${emailHash}`).get()).data() ?? {};
    check(index.userId === userRecord.uid && index.schoolId === DEMO_SCHOOL_ID && index.userType === (account.role === "parent" ? "parent" : "user"), `${account.role} email-to-school index is missing or stale.`);

    const fresh = await signInWithPassword(account.email, state.password, apiKey, bundleId);
    check(fresh.uid === userRecord.uid, `${account.role} password resolved to an unexpected identity.`);
    const decoded = await auth.verifyIdToken(fresh.idToken, true);
    check(decoded.uid === userRecord.uid, `${account.role} ID token failed server verification.`);
    const signedAccount = { ...account, ...fresh, userRecord };
    await clientGet(`userSchoolIndex/${emailHash}`, signedAccount, apiKey, bundleId);
    await clientGet(`schools/${DEMO_SCHOOL_ID}/${account.collection}/${userRecord.uid}`, signedAccount, apiKey, bundleId);
    signedIn.push(signedAccount);
  }
  pass("all three fresh password sign-ins, claims, profiles and client Rules reads");

  const admin = signedIn.find((account) => account.role === "admin")!;
  await verifyPortalSession(admin);
  pass("administrator portal session works and mutable routes remain blocked");

  if (canary) {
    const termsVersionSource = readFileSync(resolve(REPO_ROOT, "lib/services/terms_acceptance_service.dart"), "utf8");
    const termsVersion = termsVersionSource.match(/currentTermsVersion\s*=\s*'([^']+)'/)?.[1];
    check(termsVersion, "Could not resolve the current mobile Terms version.");

    const adminProfilePath = `schools/${DEMO_SCHOOL_ID}/users/${admin.uid}`;
    const adminStatus = await clientCommit(
      admin,
      apiKey,
      bundleId,
      [updateWrite(adminProfilePath, { lastLoginAt: { timestampValue: new Date().toISOString() } }, ["lastLoginAt"])],
    );
    check(adminStatus === 403, `Demo administrator client write was not denied (HTTP ${adminStatus}).`);

    for (const account of signedIn.filter((entry) => entry.role !== "admin")) {
      const path = `schools/${DEMO_SCHOOL_ID}/${account.collection}/${account.uid}`;
      const ref = db.doc(path);
      const before = (await ref.get()).data() ?? {};
      const restoreFields = [
        "lastLoginAt",
        "termsAccepted",
        "termsAcceptedAt",
        "termsAcceptedVersion",
        "termsAcceptedPlatform",
      ];
      try {
        const loginStatus = await clientCommit(
          account,
          apiKey,
          bundleId,
          [updateWrite(path, { lastLoginAt: { timestampValue: new Date().toISOString() } }, ["lastLoginAt"])],
        );
        check(loginStatus === 200, `${account.role} lastLoginAt canary failed (HTTP ${loginStatus}).`);

        const termsStatus = await clientCommit(
          account,
          apiKey,
          bundleId,
          [
            updateWrite(
              path,
              {
                termsAccepted: { booleanValue: true },
                termsAcceptedVersion: { stringValue: termsVersion },
                termsAcceptedPlatform: { stringValue: "ios" },
              },
              ["termsAccepted", "termsAcceptedVersion", "termsAcceptedPlatform"],
              [{ fieldPath: "termsAcceptedAt", setToServerValue: "REQUEST_TIME" }],
            ),
          ],
        );
        check(termsStatus === 200, `${account.role} Terms acceptance canary failed (HTTP ${termsStatus}).`);
      } finally {
        const restore = Object.fromEntries(
          restoreFields.map((field) => [
            field,
            Object.prototype.hasOwnProperty.call(before, field) ? before[field] : FieldValue.delete(),
          ]),
        );
        await ref.update(restore);
      }
    }
    pass("reversible mobile login + Terms writes work; admin write remains denied");
  } else {
    console.log("  INFO  Add --canary to exercise and automatically restore mobile login/Terms writes.");
  }

  console.log("\nREADY — the automated demo preflight passed.");
}

main()
  .catch((error) => {
    console.error(`\nNOT READY — ${error instanceof Error ? error.message : "unknown preflight failure"}`);
    process.exitCode = 1;
  })
  .finally(async () => {
    await Promise.all(getApps().map((app) => deleteApp(app)));
  });
