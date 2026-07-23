import type { Firestore } from "firebase-admin/firestore";
import type { Auth, UserRecord } from "firebase-admin/auth";
import { z } from "zod";
import { ServerOpsValidationError, type Actor } from "./audit";
import { generateTempPassword } from "./utils/tempPassword";

const configSchema = z.object({
  schoolId: z.string().min(1, "schoolId is required"),
  adminEmail: z.string().email("A valid admin email is required"),
  teacherEmail: z.string().email("A valid teacher email is required"),
  parentEmail: z.string().email("A valid parent email is required"),
});

export interface ProvisionDemoAccessConfig {
  schoolId: string;
  adminEmail: string;
  teacherEmail: string;
  parentEmail: string;
}

export interface DemoAccessAccount {
  role: "admin" | "teacher" | "parent";
  email: string;
  uid: string;
}

export interface ProvisionDemoAccessResult {
  password: string;
  dayKey: string;
  accounts: DemoAccessAccount[];
  issuedAtISO: string;
  issuedByEmail?: string;
  /** True when a same-day, unscrambled state already existed and was reused. */
  reused: boolean;
}

interface AccountSpec {
  role: "admin" | "teacher" | "parent";
  email: string;
  // Which subcollection the membership doc lives in.
  collection: "users" | "parents";
  // admin: find-or-create the Auth user + ensure the users doc. teacher/parent:
  // must already exist (a missing doc means the seed drifted — fail loudly
  // rather than mint app accounts here).
  ensure: boolean;
}

/**
 * Issue (or reuse) the shared day password for the demo school and set it on
 * the three shared accounts. Idempotent within a Sydney day: the first call
 * generates the password; later same-day calls return the existing one so a
 * second demo never invalidates a first mid-call.
 *
 * Auth is passed explicitly so this stays decoupled from any app's
 * firebase-admin singleton (mirrors createSchoolUser).
 */
export async function provisionDemoAccess(
  auth: Auth,
  db: Firestore,
  actor: Actor,
  params: {
    config: ProvisionDemoAccessConfig;
    dayKey: string;
    /** Explicit operator action: rotate even when today's state is active. */
    forceRotate?: boolean;
  }
): Promise<ProvisionDemoAccessResult> {
  const parsed = configSchema.safeParse(params.config);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { schoolId, adminEmail, teacherEmail, parentEmail } = parsed.data;
  const { dayKey } = params;
  if (!dayKey) {
    throw new ServerOpsValidationError("dayKey is required");
  }

  const reseed = (await db.doc("demoAccess/reseedStatus").get()).data();
  const demoGenerationId = reseed?.leaseId;
  if (
    reseed?.state !== "succeeded" ||
    reseed?.schoolId !== schoolId ||
    typeof demoGenerationId !== "string" ||
    demoGenerationId.length === 0
  ) {
    throw new ServerOpsValidationError(
      "The demo school has no current completed generation — reseed it before provisioning demo access."
    );
  }

  const stateRef = db.doc("demoAccess/state");

  // Ordinary preparation is idempotent within a Sydney day so one operator
  // cannot unexpectedly invalidate an in-progress customer call. The separate
  // privileged reprovision action opts into an intentional rotation.
  const existingSnap = await stateRef.get();
  const existing = existingSnap.data();
  const reusing =
    params.forceRotate !== true &&
    existingSnap.exists &&
    existing &&
    existing.dayKey === dayKey &&
    existing.scrambledAt == null &&
    typeof existing.password === "string";

  const password = reusing ? existing.password : generateTempPassword();

  const specs: AccountSpec[] = [
    { role: "admin", email: adminEmail, collection: "users", ensure: true },
    { role: "teacher", email: teacherEmail, collection: "users", ensure: false },
    { role: "parent", email: parentEmail, collection: "parents", ensure: false },
  ];

  const accounts: DemoAccessAccount[] = [];
  for (const spec of specs) {
    // Resolve the Auth uid.
    let uid: string;
    let authUser: UserRecord;
    try {
      authUser = await auth.getUserByEmail(spec.email);
      uid = authUser.uid;
    } catch {
      if (!spec.ensure) {
        throw new ServerOpsValidationError(
          `${spec.email} has no Auth account — reseed the demo school before provisioning demo access.`
        );
      }
      authUser = await auth.createUser({
        email: spec.email,
        displayName: "Lumi Demo Admin",
        emailVerified: true,
      });
      uid = authUser.uid;
    }

    // Verify (or, for the admin, ensure) demo-school membership. Never rotate an
    // account we can't prove belongs to the demo school.
    const memberRef = db
      .collection("schools")
      .doc(schoolId)
      .collection(spec.collection)
      .doc(uid);
    const memberSnap = await memberRef.get();
    if (!memberSnap.exists) {
      if (!spec.ensure) {
        throw new ServerOpsValidationError(
          `${spec.email} is not a member of the demo school (${schoolId}/${spec.collection}) — reseed before provisioning.`
        );
      }
      await memberRef.set({
        email: spec.email,
        fullName: "Lumi Demo Admin",
        role: "schoolAdmin",
        classIds: [],
        linkedChildren: [],
        isActive: true,
        createdAt: new Date(),
      });
    }

    if (!reusing) {
      authUser = await auth.updateUser(uid, {
        password,
        emailVerified: true,
        // Demo accounts must remain friction-free. The shared administrator's
        // TOTP exception is safe only while it is coupled to read-only claims.
        multiFactor: { enrolledFactors: [] },
      });
    }
    // Replace, rather than spread, custom claims. These are shared accounts;
    // preserving a stale developer/impersonation/admin capability would turn
    // a harmless demo credential into a privileged production credential.
    const claims: Record<string, unknown> = {
      demoAccount: true,
      demoSchoolId: schoolId,
      demoGenerationId,
      schoolId,
    };
    if (spec.role === "admin") {
      claims.demoAdminMfaExempt = true;
      claims.demoReadOnly = true;
    }
    await auth.setCustomUserClaims(uid, claims);
    accounts.push({ role: spec.role, email: spec.email, uid });
  }

  if (reusing) {
    const issuedAt = existing.issuedAt;
    const issuedAtISO =
      issuedAt && typeof issuedAt.toDate === "function"
        ? issuedAt.toDate().toISOString()
        : new Date().toISOString();
    return {
      password,
      dayKey,
      accounts,
      issuedAtISO,
      issuedByEmail: existing.issuedBy?.email,
      reused: true,
    };
  }

  const issuedAt = new Date();
  await stateRef.set({
    dayKey,
    password,
    issuedAt,
    issuedBy: { uid: actor.uid, email: actor.email ?? null },
    accounts,
    scrambledAt: null,
    lastEmail: null,
  });

  return {
    password,
    dayKey,
    accounts,
    issuedAtISO: issuedAt.toISOString(),
    issuedByEmail: actor.email,
    reused: false,
  };
}
