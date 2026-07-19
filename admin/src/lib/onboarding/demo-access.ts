import "server-only";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import { provisionDemoAccess, type DemoAccessAccount } from "@lumi/server-ops";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import { readDemoAccessConfig, sydneyDayKey } from "@/lib/firestore/demo-access";
import { runDemoReseed } from "@/lib/demo/reseed";

// 400/409-class errors surfaced to the operator (mirrors OnboardingProvisionError).
export class DemoAccessError extends Error {
  status: number;
  constructor(message: string, status = 400) {
    super(message);
    this.name = "DemoAccessError";
    this.status = status;
  }
}

export interface ProvisionDemoAccessResponse {
  password: string;
  accounts: DemoAccessAccount[];
  dayKey: string;
  reused: boolean;
  issuedByEmail?: string;
}

export type DemoPreparationMode = "provision" | "reprovision";

// "Provision today's demo password": issue (or reuse) the day password and set
// it on the three shared accounts.
export async function provisionDemoAccessForOnboarding(
  actor: { uid: string; email?: string },
  onboardingId: string,
  mode: DemoPreparationMode = "provision",
): Promise<ProvisionDemoAccessResponse> {
  const db = getAdminDb();
  const obRef = db.collection("schoolOnboarding").doc(onboardingId);
  const obSnap = await obRef.get();
  if (!obSnap.exists) {
    throw new DemoAccessError("Onboarding request not found", 404);
  }
  if (obSnap.data()?.status !== "demo") {
    throw new DemoAccessError(
      "Demo access can be prepared only from an active demo request.",
      409,
    );
  }

  const config = await readDemoAccessConfig();
  const dayKey = sydneyDayKey();

  // Decide before issuing credentials. provisionDemoAccess would report
  // reused:false for exactly this state; refreshing first ensures interactive
  // claims are never finalised against stale/partially rebuilt demo data.
  const stateSnap = await db.doc("demoAccess/state").get();
  const state = stateSnap.data();
  const wouldReuse =
    stateSnap.exists &&
    state?.dayKey === dayKey &&
    state?.scrambledAt == null &&
    typeof state?.password === "string";
  const forceRefresh = mode === "reprovision";
  if (forceRefresh || !wouldReuse) {
    await runDemoReseed(actor, "provision");
  }

  const result = await provisionDemoAccess(getAdminAuth(), db, actor, {
    config: {
      schoolId: config.schoolId,
      adminEmail: config.adminEmail,
      teacherEmail: config.teacherEmail,
      parentEmail: config.parentEmail,
    },
    dayKey,
    forceRotate: forceRefresh,
  });

  await obRef.update({
    demoAccessProvisionedAt: FieldValue.serverTimestamp(),
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });

  await logAuditEvent({
    action: "onboarding.demoProvision",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "onboarding",
    targetId: onboardingId,
    schoolId: config.schoolId,
    after: {
      dayKey,
      mode,
      reused: result.reused,
      accounts: result.accounts.length,
    },
  }).catch((e) => {
    console.error("[onboarding] audit log failed for onboarding.demoProvision", e);
  });

  return {
    password: result.password,
    accounts: result.accounts,
    dayKey: result.dayKey,
    reused: result.reused,
    issuedByEmail: result.issuedByEmail,
  };
}

export interface SendDemoAccessEmailResponse {
  to: string;
  queuedId: string;
}

// "Email demo details": queue a demoAccessEmails doc (the trigger sends it and
// writes the real status back). Requires a live (today, unscrambled) day
// password, so we never queue an email that would resolve to a stale password.
export async function sendDemoAccessEmail(
  actor: { uid: string; email?: string },
  onboardingId: string
): Promise<SendDemoAccessEmailResponse> {
  const db = getAdminDb();
  const obRef = db.collection("schoolOnboarding").doc(onboardingId);
  const obSnap = await obRef.get();
  if (!obSnap.exists) {
    throw new DemoAccessError("Onboarding request not found", 404);
  }
  const ob = obSnap.data()!;
  const to = (ob.contactEmail as string) || "";
  if (!to) {
    throw new DemoAccessError(
      "This request has no contact email to send to.",
      400
    );
  }

  const today = sydneyDayKey();
  const [stateSnap, readinessSnap] = await Promise.all([
    db.doc("demoAccess/state").get(),
    db.doc("demoAccess/readinessStatus").get(),
  ]);
  const state = stateSnap.data();
  if (!stateSnap.exists || !state) {
    throw new DemoAccessError(
      "No demo password has been issued yet — provision today's password first.",
      409
    );
  }
  if (state.dayKey !== today || state.scrambledAt != null) {
    throw new DemoAccessError(
      "Today's demo password isn't active — provision it again before emailing.",
      409
    );
  }
  const readiness = readinessSnap.data();
  if (
    !readinessSnap.exists ||
    readiness?.ready !== true ||
    readiness?.state !== "ready" ||
    readiness?.dayKey !== today
  ) {
    throw new DemoAccessError(
      "Prepare and verify today's demo before emailing its credentials.",
      409
    );
  }

  const queueRef = db.collection("demoAccessEmails").doc();
  await queueRef.set({
    onboardingId,
    to,
    contactPerson: (ob.contactPerson as string) || "",
    schoolName: (ob.schoolName as string) || "",
    dayKey: today,
    requestedBy: { uid: actor.uid, email: actor.email ?? null },
    status: "queued",
    createdAt: FieldValue.serverTimestamp(),
  });

  await obRef.update({
    demoEmailLastSentAt: FieldValue.serverTimestamp(),
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });

  await logAuditEvent({
    action: "onboarding.demoEmail",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "onboarding",
    targetId: onboardingId,
    after: { to, dayKey: today, queuedId: queueRef.id },
  }).catch((e) => {
    console.error("[onboarding] audit log failed for onboarding.demoEmail", e);
  });

  return { to, queuedId: queueRef.id };
}
