import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import test from "node:test";
import type { Auth } from "firebase-admin/auth";
import type { Firestore } from "firebase-admin/firestore";
import {
  DemoPreflightError,
  runDemoPreflight,
} from "../src/lib/demo/preflight-core";

const schoolId = "lumi_demo_primary_school";
const password = "DO-NOT-RETURN-this-password";
const accounts = {
  "support+demo@lumi-reading.com": { role: "admin", uid: "secret-admin-uid" },
  "support+demo.teacher@lumi-reading.com": {
    role: "teacher",
    uid: "secret-teacher-uid",
  },
  "support+demo.parent@lumi-reading.com": {
    role: "parent",
    uid: "secret-parent-uid",
  },
} as const;

function snap(data: Record<string, unknown> | undefined) {
  return { exists: data !== undefined, data: () => data };
}

function createHarness(failingRole?: string) {
  const restoredPaths: string[] = [];
  const byPath = new Map<string, Record<string, unknown>>([
    [`schools/${schoolId}`, { isDemo: true }],
    [
      "platformConfig/demoAccess",
      {
        schoolId,
        adminEmail: "support+demo@lumi-reading.com",
        teacherEmail: "support+demo.teacher@lumi-reading.com",
        parentEmail: "support+demo.parent@lumi-reading.com",
      },
    ],
    [
      "demoAccess/state",
      { dayKey: "2026-07-19", scrambledAt: null, password },
    ],
    ["demoAccess/reseedStatus", { state: "succeeded", schoolId }],
  ]);

  for (const [email, account] of Object.entries(accounts)) {
    const collection = account.role === "parent" ? "parents" : "users";
    byPath.set(`schools/${schoolId}/${collection}/${account.uid}`, {
      role: account.role === "admin" ? "schoolAdmin" : account.role,
      schoolId,
      isActive: true,
      ...(account.role === "teacher" ? { classIds: ["private-class"] } : {}),
      ...(account.role === "parent"
        ? { linkedChildren: ["private-child-one", "private-child-two"] }
        : {}),
    });
    const emailHash = createHash("sha256")
      .update(email.toLowerCase())
      .digest("hex");
    byPath.set(`userSchoolIndex/${emailHash}`, {
      userId: account.uid,
      schoolId,
      userType: account.role === "parent" ? "parent" : "user",
    });
  }

  const db = {
    doc(path: string) {
      return {
        get: async () => snap(byPath.get(path)),
        update: async () => {
          restoredPaths.push(path);
        },
      };
    },
    collection() {
      return {
        count: () => ({
          get: async () => ({ data: () => ({ count: 500 }) }),
        }),
      };
    },
  } as unknown as Firestore;

  const auth = {
    getUserByEmail: async (email: keyof typeof accounts) => {
      const account = accounts[email];
      return {
        uid: account.uid,
        disabled: false,
        emailVerified: true,
        multiFactor: { enrolledFactors: [] },
        customClaims: {
          demoAccount: true,
          demoSchoolId: schoolId,
          schoolId,
          ...(account.role === "admin"
            ? { demoAdminMfaExempt: true, demoReadOnly: true }
            : {}),
        },
      };
    },
    verifyIdToken: async (token: string) => ({ uid: token.replace("token-", "") }),
  } as unknown as Auth;

  const fetchImpl = async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    if (url.includes("accounts:signInWithPassword")) {
      const body = JSON.parse(String(init?.body)) as { email: keyof typeof accounts };
      const account = accounts[body.email];
      if (account.role === failingRole) {
        return new Response("{}", { status: 400 });
      }
      return Response.json({
        localId: account.uid,
        idToken: `token-${account.uid}`,
      });
    }
    if (url.includes("firestore.googleapis.com")) {
      if (url.includes("documents:commit")) {
        const authorization = new Headers(init?.headers).get("authorization") ?? "";
        return new Response("{}", {
          status: authorization.includes("secret-admin-uid") ? 403 : 200,
        });
      }
      return new Response("{}", { status: 200 });
    }
    if (url.endsWith("/api/auth/session")) {
      return new Response("{}", {
        status: 200,
        headers: { "set-cookie": "__session=redacted; HttpOnly; Secure" },
      });
    }
    if (url.endsWith("/api/auth/me")) {
      return new Response("{}", { status: 200 });
    }
    if (url.endsWith("/api/profile")) {
      return new Response("{}", { status: 401 });
    }
    throw new Error(`Unexpected test request: ${url}`);
  };

  return { auth, db, fetchImpl: fetchImpl as typeof fetch, restoredPaths };
}

function options(failingRole?: string) {
  const harness = createHarness(failingRole);
  return {
    ...harness,
    projectId: "lumi-ninc-au",
    demoSchoolId: schoolId,
    portalOrigin: "https://lumi-school-admin-au.web.app",
    apiKey: "public-firebase-key",
    termsVersion: "2026-07-10",
    canary: false,
    now: new Date("2026-07-19T00:00:00.000Z"),
  };
}

test("preflight returns only redacted structured readiness results", async () => {
  const result = await runDemoPreflight(options());
  assert.equal(result.ready, true);
  assert.deepEqual(
    result.checks.map(({ key, status }) => ({ key, status })),
    [
      { key: "tenant", status: "pass" },
      { key: "credential", status: "pass" },
      { key: "content", status: "pass" },
      { key: "identities", status: "pass" },
      { key: "portal", status: "pass" },
      { key: "canary", status: "skipped" },
    ],
  );
  const serialised = JSON.stringify(result);
  for (const forbidden of [
    password,
    "@lumi-reading.com",
    "secret-admin-uid",
    "secret-teacher-uid",
    "secret-parent-uid",
    "private-child-one",
    "private-class",
    "token-",
  ]) {
    assert.equal(serialised.includes(forbidden), false, `leaked ${forbidden}`);
  }
});

test("failed live sign-in returns a redacted not-ready receipt", async () => {
  await assert.rejects(
    () => runDemoPreflight(options("teacher")),
    (error: unknown) => {
      assert.ok(error instanceof DemoPreflightError);
      assert.equal(error.result.ready, false);
      assert.equal(error.result.checks.at(-1)?.key, "identities");
      assert.equal(error.result.checks.at(-1)?.status, "fail");
      assert.equal(JSON.stringify(error.result).includes(password), false);
      assert.equal(JSON.stringify(error.result).includes("secret-teacher-uid"), false);
      return true;
    },
  );
});

test("canary denies admin writes and restores parent and teacher profiles", async () => {
  const canaryOptions = { ...options(), canary: true };
  const result = await runDemoPreflight(canaryOptions);
  assert.equal(result.ready, true);
  assert.equal(result.checks.at(-1)?.key, "canary");
  assert.equal(result.checks.at(-1)?.status, "pass");
  assert.deepEqual(canaryOptions.restoredPaths.sort(), [
    `schools/${schoolId}/parents/secret-parent-uid`,
    `schools/${schoolId}/users/secret-teacher-uid`,
  ]);
});

test("server and mobile Terms canary versions stay in sync", () => {
  const root = resolve(import.meta.dirname, "../..");
  const server = readFileSync(
    resolve(root, "admin/src/lib/demo/preflight.ts"),
    "utf8",
  );
  const mobile = readFileSync(
    resolve(root, "lib/services/terms_acceptance_service.dart"),
    "utf8",
  );
  const serverVersion = server.match(
    /CURRENT_MOBILE_TERMS_VERSION\s*=\s*"([^"]+)"/,
  )?.[1];
  const mobileVersion = mobile.match(
    /currentTermsVersion\s*=\s*'([^']+)'/,
  )?.[1];
  assert.ok(serverVersion);
  assert.equal(serverVersion, mobileVersion);
  assert.match(
    server,
    /SUPER_ADMIN_ORIGIN\s*=\s*"https:\/\/lumi-dev-admin-au\.web\.app"/,
    "server preflight must identify the deployed referrer-restricted admin site",
  );
});
