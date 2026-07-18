import { createHash } from "node:crypto";
import type { Auth, UserRecord } from "firebase-admin/auth";
import { FieldValue, type Firestore } from "firebase-admin/firestore";

export type DemoPreflightCheckStatus = "pass" | "fail" | "skipped";

export interface DemoPreflightCheck {
  key: "tenant" | "credential" | "content" | "identities" | "portal" | "canary";
  label: string;
  status: DemoPreflightCheckStatus;
  detail: string;
}

export interface DemoPreflightResult {
  ready: boolean;
  dayKey: string;
  checkedAt: string;
  checks: DemoPreflightCheck[];
}

export interface DemoPreflightOptions {
  auth: Auth;
  db: Firestore;
  projectId: string;
  demoSchoolId: string;
  portalOrigin: string;
  apiKey: string;
  clientAppHeaders?: Record<string, string>;
  termsVersion: string;
  canary?: boolean;
  now?: Date;
  fetchImpl?: typeof fetch;
}

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

class SafePreflightAssertion extends Error {}

export class DemoPreflightError extends Error {
  readonly result: DemoPreflightResult;

  constructor(message: string, result: DemoPreflightResult) {
    super(message);
    this.name = "DemoPreflightError";
    this.result = result;
  }
}

function ensure(condition: unknown, message: string): asserts condition {
  if (!condition) throw new SafePreflightAssertion(message);
}

function sydneyDayKey(now: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Australia/Sydney",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

function exactObject(
  actual: Record<string, unknown>,
  expected: Record<string, unknown>,
): boolean {
  const actualKeys = Object.keys(actual).sort();
  const expectedKeys = Object.keys(expected).sort();
  return (
    JSON.stringify(actualKeys) === JSON.stringify(expectedKeys) &&
    expectedKeys.every((key) => actual[key] === expected[key])
  );
}

function firestoreUrl(projectId: string, path: string, apiKey: string): string {
  const encodedPath = path
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents/${encodedPath}?key=${encodeURIComponent(apiKey)}`;
}

function clientHeaders(
  idToken: string,
  appHeaders: Record<string, string>,
): Record<string, string> {
  return {
    ...appHeaders,
    authorization: `Bearer ${idToken}`,
    "content-type": "application/json",
  };
}

async function signInWithPassword(
  role: DemoRole,
  email: string,
  password: string,
  apiKey: string,
  appHeaders: Record<string, string>,
  fetchImpl: typeof fetch,
): Promise<{ uid: string; idToken: string }> {
  const response = await fetchImpl(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: { ...appHeaders, "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
      redirect: "manual",
    },
  );
  ensure(
    response.ok,
    `Fresh password sign-in failed for the demo ${role} (HTTP ${response.status}). Re-run preparation and retry.`,
  );
  const body = (await response.json()) as {
    localId?: unknown;
    idToken?: unknown;
  };
  ensure(
    typeof body.localId === "string" && body.localId.length > 0,
    `The demo ${role} sign-in omitted its account identifier.`,
  );
  ensure(
    typeof body.idToken === "string" && body.idToken.length > 0,
    `The demo ${role} sign-in omitted its identity token.`,
  );
  return { uid: body.localId, idToken: body.idToken };
}

async function clientGet(
  projectId: string,
  path: string,
  account: SignedInAccount,
  apiKey: string,
  appHeaders: Record<string, string>,
  fetchImpl: typeof fetch,
): Promise<void> {
  const response = await fetchImpl(firestoreUrl(projectId, path, apiKey), {
    headers: clientHeaders(account.idToken, appHeaders),
    redirect: "manual",
  });
  ensure(
    response.status === 200,
    `The demo ${account.role} could not read its own profile through production security rules (HTTP ${response.status}).`,
  );
}

async function clientCommit(
  projectId: string,
  account: SignedInAccount,
  apiKey: string,
  appHeaders: Record<string, string>,
  writes: unknown[],
  fetchImpl: typeof fetch,
): Promise<number> {
  const response = await fetchImpl(
    `https://firestore.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/databases/(default)/documents:commit?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: clientHeaders(account.idToken, appHeaders),
      body: JSON.stringify({ writes }),
      redirect: "manual",
    },
  );
  return response.status;
}

function documentName(projectId: string, path: string): string {
  return `projects/${projectId}/databases/(default)/documents/${path}`;
}

function updateWrite(
  projectId: string,
  path: string,
  fields: Record<string, unknown>,
  mask: string[],
  transforms: unknown[] = [],
): unknown {
  return {
    update: { name: documentName(projectId, path), fields },
    updateMask: { fieldPaths: mask },
    ...(transforms.length > 0 ? { updateTransforms: transforms } : {}),
    currentDocument: { exists: true },
  };
}

async function verifyPortalSession(
  portalOrigin: string,
  admin: SignedInAccount,
  fetchImpl: typeof fetch,
): Promise<void> {
  const sessionResponse = await fetchImpl(`${portalOrigin}/api/auth/session`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ idToken: admin.idToken }),
    redirect: "manual",
  });
  ensure(
    sessionResponse.status === 200,
    `The demo administrator could not create a school-portal session (HTTP ${sessionResponse.status}).`,
  );
  const cookieHeader = sessionResponse.headers.get("set-cookie");
  ensure(cookieHeader, "The school portal did not return its protected session cookie.");
  const cookie = cookieHeader.split(";", 1)[0];

  const meResponse = await fetchImpl(`${portalOrigin}/api/auth/me`, {
    headers: { cookie },
    redirect: "manual",
  });
  ensure(
    meResponse.status === 200,
    `The demo administrator could not load the school portal (HTTP ${meResponse.status}).`,
  );

  // Empty PATCH is harmless. A mutable account would reach validation and
  // return 400; the read-only shared demo account must stop at auth with 401.
  const mutationResponse = await fetchImpl(`${portalOrigin}/api/profile`, {
    method: "PATCH",
    headers: { cookie, "content-type": "application/json" },
    body: "{}",
    redirect: "manual",
  });
  ensure(
    mutationResponse.status === 401,
    `The shared demo administrator was not rejected by a mutable portal route (HTTP ${mutationResponse.status}).`,
  );
}

function safeStageMessage(error: unknown): string {
  if (error instanceof SafePreflightAssertion) return error.message;
  return "The live verification encountered an internal error. Check server logs and retry.";
}

/**
 * Exercises the real customer-facing authentication, Firestore Rules and
 * school-portal boundaries. Results are deliberately redacted: no password,
 * token, UID, child identity or Firestore document ID is returned.
 */
export async function runDemoPreflight(
  options: DemoPreflightOptions,
): Promise<DemoPreflightResult> {
  const now = options.now ?? new Date();
  const checkedAt = now.toISOString();
  const dayKey = sydneyDayKey(now);
  const checks: DemoPreflightCheck[] = [];
  const appHeaders = options.clientAppHeaders ?? {};
  const fetchImpl = options.fetchImpl ?? fetch;
  const portalUrl = new URL(options.portalOrigin);

  ensure(options.projectId.length > 0, "The Firebase project is not configured.");
  ensure(options.demoSchoolId.length > 0, "The immutable demo school is not configured.");
  ensure(options.apiKey.length > 0, "The Firebase client key is not configured.");
  ensure(options.termsVersion.length > 0, "The current mobile Terms version is not configured.");
  ensure(
    portalUrl.protocol === "https:" && portalUrl.origin === options.portalOrigin,
    "The school portal origin is invalid.",
  );

  const result = (): DemoPreflightResult => ({
    ready: checks.every((check) => check.status !== "fail"),
    dayKey,
    checkedAt,
    checks: [...checks],
  });

  const stage = async (
    key: DemoPreflightCheck["key"],
    label: string,
    successDetail: string,
    action: () => Promise<void>,
  ): Promise<void> => {
    try {
      await action();
      checks.push({ key, label, status: "pass", detail: successDetail });
    } catch (error) {
      const message = safeStageMessage(error);
      checks.push({ key, label, status: "fail", detail: message });
      throw new DemoPreflightError(message, { ...result(), ready: false });
    }
  };

  let config: FirebaseFirestore.DocumentData = {};
  let state: FirebaseFirestore.DocumentData = {};
  let accounts: SharedAccount[] = [];
  let signedIn: SignedInAccount[] = [];

  await stage(
    "tenant",
    "Demo tenant and reseed",
    "The isolated demo school and its latest completed reseed are valid.",
    async () => {
      const [schoolSnap, configSnap, stateSnap, reseedSnap] = await Promise.all([
        options.db.doc(`schools/${options.demoSchoolId}`).get(),
        options.db.doc("platformConfig/demoAccess").get(),
        options.db.doc("demoAccess/state").get(),
        options.db.doc("demoAccess/reseedStatus").get(),
      ]);
      ensure(
        schoolSnap.exists && schoolSnap.data()?.isDemo === true,
        "The configured demo school is missing or is not authoritatively marked as demo data.",
      );
      ensure(configSnap.exists, "The demo-access configuration is missing.");
      ensure(stateSnap.exists, "No demo password has been provisioned.");
      ensure(
        reseedSnap.exists && reseedSnap.data()?.state === "succeeded",
        "The latest demo refresh did not complete successfully.",
      );
      ensure(
        reseedSnap.data()?.schoolId === options.demoSchoolId,
        "The latest refresh points at the wrong school.",
      );
      config = configSnap.data() ?? {};
      state = stateSnap.data() ?? {};
    },
  );

  await stage(
    "credential",
    "Today’s demo credential",
    "Today’s Sydney-date credential is active and unscrambled.",
    async () => {
      accounts = [
        {
          role: "admin",
          email: config.adminEmail,
          collection: "users",
          expectedProfileRole: "schoolAdmin",
        },
        {
          role: "teacher",
          email: config.teacherEmail,
          collection: "users",
          expectedProfileRole: "teacher",
        },
        {
          role: "parent",
          email: config.parentEmail,
          collection: "parents",
          expectedProfileRole: "parent",
        },
      ];
      ensure(
        config.schoolId === options.demoSchoolId,
        "The demo-access configuration points at the wrong school.",
      );
      ensure(
        accounts.every(
          (account) =>
            typeof account.email === "string" &&
            account.email.endsWith("@lumi-reading.com"),
        ),
        "One or more shared demo identities is outside the controlled Lumi mailbox.",
      );
      ensure(
        state.dayKey === dayKey && state.scrambledAt == null,
        "Today’s demo password is not active. Prepare today’s demo again.",
      );
      ensure(
        typeof state.password === "string" && state.password.length >= 12,
        "Today’s demo credential is missing or malformed.",
      );
    },
  );

  await stage(
    "content",
    "Customer-facing demo content",
    "Students, classes, books, allocations and reading history are populated.",
    async () => {
      const [studentCount, logCount, classCount, bookCount, allocationCount] =
        await Promise.all([
          options.db
            .collection(`schools/${options.demoSchoolId}/students`)
            .count()
            .get(),
          options.db
            .collection(`schools/${options.demoSchoolId}/readingLogs`)
            .count()
            .get(),
          options.db
            .collection(`schools/${options.demoSchoolId}/classes`)
            .count()
            .get(),
          options.db
            .collection(`schools/${options.demoSchoolId}/books`)
            .count()
            .get(),
          options.db
            .collection(`schools/${options.demoSchoolId}/allocations`)
            .count()
            .get(),
        ]);
      ensure(studentCount.data().count >= 16, "The demo school has fewer than 16 students.");
      ensure(logCount.data().count >= 450, "The demo school has fewer than 450 reading logs.");
      ensure(classCount.data().count >= 2, "The demo school has fewer than two classes.");
      ensure(bookCount.data().count >= 3, "The demo school has fewer than three books.");
      ensure(allocationCount.data().count >= 2, "The demo school has fewer than two allocations.");
    },
  );

  await stage(
    "identities",
    "Admin, teacher and parent access",
    "All three fresh password sign-ins, exact claims, profiles, indexes and production Rules reads passed.",
    async () => {
      const verified: SignedInAccount[] = [];
      for (const account of accounts) {
        const userRecord = await options.auth.getUserByEmail(account.email);
        ensure(
          !userRecord.disabled && userRecord.emailVerified,
          `The demo ${account.role} identity is disabled or unverified.`,
        );
        ensure(
          (userRecord.multiFactor?.enrolledFactors ?? []).length === 0,
          `The demo ${account.role} unexpectedly requires MFA.`,
        );
        const expectedClaims: Record<string, unknown> = {
          demoAccount: true,
          demoSchoolId: options.demoSchoolId,
          schoolId: options.demoSchoolId,
          ...(account.role === "admin"
            ? { demoAdminMfaExempt: true, demoReadOnly: true }
            : {}),
        };
        ensure(
          exactObject(userRecord.customClaims ?? {}, expectedClaims),
          `The demo ${account.role} claims drifted from the approved allowlist.`,
        );

        const profileRef = options.db.doc(
          `schools/${options.demoSchoolId}/${account.collection}/${userRecord.uid}`,
        );
        const profileSnap = await profileRef.get();
        const profile = profileSnap.data() ?? {};
        ensure(
          profileSnap.exists &&
            profile.role === account.expectedProfileRole &&
            profile.schoolId === options.demoSchoolId &&
            profile.isActive !== false,
          `The demo ${account.role} profile is missing, inactive or assigned incorrectly.`,
        );
        if (account.role === "teacher") {
          ensure(
            Array.isArray(profile.classIds) && profile.classIds.length > 0,
            "The demo teacher has no assigned class.",
          );
        }
        if (account.role === "parent") {
          ensure(
            Array.isArray(profile.linkedChildren) && profile.linkedChildren.length >= 2,
            "The demo parent is not linked to both showcase students.",
          );
        }

        const emailHash = createHash("sha256")
          .update(account.email.toLowerCase().trim())
          .digest("hex");
        const index = (
          await options.db.doc(`userSchoolIndex/${emailHash}`).get()
        ).data() ?? {};
        ensure(
          index.userId === userRecord.uid &&
            index.schoolId === options.demoSchoolId &&
            index.userType === (account.role === "parent" ? "parent" : "user"),
          `The demo ${account.role} email-to-school index is missing or stale.`,
        );

        const fresh = await signInWithPassword(
          account.role,
          account.email,
          state.password,
          options.apiKey,
          appHeaders,
          fetchImpl,
        );
        ensure(
          fresh.uid === userRecord.uid,
          `The demo ${account.role} password resolved to an unexpected account.`,
        );
        const decoded = await options.auth.verifyIdToken(fresh.idToken, true);
        ensure(
          decoded.uid === userRecord.uid,
          `The demo ${account.role} token failed server verification.`,
        );
        const signedAccount: SignedInAccount = {
          ...account,
          ...fresh,
          userRecord,
        };
        await clientGet(
          options.projectId,
          `userSchoolIndex/${emailHash}`,
          signedAccount,
          options.apiKey,
          appHeaders,
          fetchImpl,
        );
        await clientGet(
          options.projectId,
          `schools/${options.demoSchoolId}/${account.collection}/${userRecord.uid}`,
          signedAccount,
          options.apiKey,
          appHeaders,
          fetchImpl,
        );
        verified.push(signedAccount);
      }
      signedIn = verified;
    },
  );

  await stage(
    "portal",
    "School administrator portal",
    "The demo administrator can open the portal and remains read-only.",
    async () => {
      const admin = signedIn.find((account) => account.role === "admin");
      ensure(admin, "The verified demo administrator is unavailable.");
      await verifyPortalSession(options.portalOrigin, admin, fetchImpl);
    },
  );

  if (options.canary) {
    await stage(
      "canary",
      "Reversible mobile write canary",
      "Parent and teacher login/Terms writes passed and were restored; the administrator write remained denied.",
      async () => {
        const admin = signedIn.find((account) => account.role === "admin");
        ensure(admin, "The verified demo administrator is unavailable.");
        const adminProfilePath = `schools/${options.demoSchoolId}/users/${admin.uid}`;
        const adminStatus = await clientCommit(
          options.projectId,
          admin,
          options.apiKey,
          appHeaders,
          [
            updateWrite(
              options.projectId,
              adminProfilePath,
              { lastLoginAt: { timestampValue: new Date().toISOString() } },
              ["lastLoginAt"],
            ),
          ],
          fetchImpl,
        );
        ensure(
          adminStatus === 403,
          `The demo administrator client write was not denied (HTTP ${adminStatus}).`,
        );

        for (const account of signedIn.filter((entry) => entry.role !== "admin")) {
          const path = `schools/${options.demoSchoolId}/${account.collection}/${account.uid}`;
          const ref = options.db.doc(path);
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
              options.projectId,
              account,
              options.apiKey,
              appHeaders,
              [
                updateWrite(
                  options.projectId,
                  path,
                  { lastLoginAt: { timestampValue: new Date().toISOString() } },
                  ["lastLoginAt"],
                ),
              ],
              fetchImpl,
            );
            ensure(
              loginStatus === 200,
              `The demo ${account.role} login write failed (HTTP ${loginStatus}).`,
            );

            const termsStatus = await clientCommit(
              options.projectId,
              account,
              options.apiKey,
              appHeaders,
              [
                updateWrite(
                  options.projectId,
                  path,
                  {
                    termsAccepted: { booleanValue: true },
                    termsAcceptedVersion: { stringValue: options.termsVersion },
                    termsAcceptedPlatform: { stringValue: "ios" },
                  },
                  [
                    "termsAccepted",
                    "termsAcceptedVersion",
                    "termsAcceptedPlatform",
                  ],
                  [
                    {
                      fieldPath: "termsAcceptedAt",
                      setToServerValue: "REQUEST_TIME",
                    },
                  ],
                ),
              ],
              fetchImpl,
            );
            ensure(
              termsStatus === 200,
              `The demo ${account.role} Terms write failed (HTTP ${termsStatus}).`,
            );
          } finally {
            const restore = Object.fromEntries(
              restoreFields.map((field) => [
                field,
                Object.prototype.hasOwnProperty.call(before, field)
                  ? before[field]
                  : FieldValue.delete(),
              ]),
            );
            await ref.update(restore);
          }
        }
      },
    );
  } else {
    checks.push({
      key: "canary",
      label: "Reversible mobile write canary",
      status: "skipped",
      detail: "Run the canary mode to exercise and automatically restore mobile login and Terms writes.",
    });
  }

  return { ...result(), ready: true };
}
