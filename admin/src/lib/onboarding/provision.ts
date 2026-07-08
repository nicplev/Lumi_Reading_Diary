import "server-only";
import { FieldValue } from "firebase-admin/firestore";
import { getAdminAuth, getAdminDb } from "@/lib/firebase-admin";
import { createSchool, createSchoolUser } from "@lumi/server-ops";
import {
  getCurrentAcademicYear,
  upsertSubscription,
} from "@/lib/firestore/school-subscriptions";
import { createSchoolCode } from "@/lib/firestore/school-codes";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import type { SubscriptionStatus } from "@lumi/types";

// Composes the deployed provisioning primitives into a single "provision a
// school from an onboarding request" action. Ordering follows the create-school
// route (#304): createSchool → comp subscription (which the trigger turns into
// live school.access) → school-admin account → invite link. Guarded so it can
// never create a duplicate school for an already-linked request.

export class OnboardingProvisionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OnboardingProvisionError";
  }
}

export interface ProvisionSchoolParams {
  onboardingId: string;
  timezone: string;
  adminEmail: string;
  adminFullName: string;
  subscriptionStatus?: SubscriptionStatus;
  createJoinCode?: boolean;
}

export interface ProvisionSchoolResult {
  schoolId: string;
  /** Password-setup link for the new admin (best-effort). */
  inviteLink?: string;
  /** Teacher self-join code, if requested (best-effort). */
  joinCode?: string;
}

export async function provisionSchoolFromOnboarding(
  actor: { uid: string; email?: string },
  params: ProvisionSchoolParams
): Promise<ProvisionSchoolResult> {
  const db = getAdminDb();
  const auth = getAdminAuth();

  const obRef = db.collection("schoolOnboarding").doc(params.onboardingId);
  const obSnap = await obRef.get();
  if (!obSnap.exists) {
    throw new OnboardingProvisionError("Onboarding request not found");
  }
  const ob = obSnap.data()!;
  if (ob.schoolId) {
    throw new OnboardingProvisionError(
      "This request is already linked to a school — provisioning again would create a duplicate."
    );
  }
  const schoolName = (ob.schoolName as string) || "New School";

  // 1. The school doc (levelSchema:"aToZ", isActive:true set by createSchool).
  const { id: schoolId } = await createSchool(db, actor, {
    name: schoolName,
    timezone: params.timezone,
    contactEmail: (ob.contactEmail as string) || undefined,
    contactPhone: (ob.contactPhone as string) || undefined,
  });

  // 2. Free (comp) subscription for the current year → onSchoolSubscriptionWrite
  //    materialises school.access = active. This is the "switch it on" step.
  const academicYear = await getCurrentAcademicYear();
  await upsertSubscription({
    schoolId,
    academicYear,
    status: params.subscriptionStatus ?? "comp",
    updatedBy: actor.uid,
  });

  // 3. School-admin account (find-or-create Auth user by email).
  const { id: adminUserId } = await createSchoolUser(auth, db, actor, {
    schoolId,
    email: params.adminEmail,
    fullName: params.adminFullName,
    role: "schoolAdmin",
  });

  // 4. Password-setup link to send the admin (they have no password yet).
  let inviteLink: string | undefined;
  try {
    inviteLink = await auth.generatePasswordResetLink(params.adminEmail);
  } catch (e) {
    console.error("[onboarding] admin invite link failed", e);
  }

  // 5. Optional teacher self-join code.
  let joinCode: string | undefined;
  if (params.createJoinCode) {
    try {
      const res = await createSchoolCode({
        schoolId,
        schoolName,
        createdBy: actor.uid,
      });
      joinCode = res.code;
    } catch (e) {
      console.error("[onboarding] join code failed", e);
    }
  }

  // 6. Link + advance the onboarding record (store the admin for later resend).
  await obRef.update({
    schoolId,
    adminUserId,
    adminEmail: params.adminEmail,
    status: "setupInProgress",
    currentStep: "importData",
    completedSteps: FieldValue.arrayUnion("schoolInfo", "adminAccount"),
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });

  await logAuditEvent({
    action: "onboarding.provision",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "onboarding",
    targetId: params.onboardingId,
    schoolId,
    after: {
      schoolId,
      subscriptionStatus: params.subscriptionStatus ?? "comp",
      adminEmail: params.adminEmail,
      joinCodeCreated: !!joinCode,
    },
  }).catch((e) => {
    console.error("[onboarding] audit log failed for onboarding.provision", e);
  });

  return { schoolId, inviteLink, joinCode };
}

// Re-generate the school-admin's password-setup link on demand — the link is
// one-shot at provision time and no email is sent, so this is how an operator
// recovers it. Prefers the adminEmail stored on the request; falls back to the
// linked school's first schoolAdmin (covers requests provisioned before the
// field was stored).
export async function regenerateAdminSetupLink(
  actor: { uid: string; email?: string },
  onboardingId: string
): Promise<{ email: string; link: string }> {
  const db = getAdminDb();
  const auth = getAdminAuth();

  const obSnap = await db
    .collection("schoolOnboarding")
    .doc(onboardingId)
    .get();
  if (!obSnap.exists) {
    throw new OnboardingProvisionError("Onboarding request not found");
  }
  const ob = obSnap.data()!;
  const schoolId = ob.schoolId as string | undefined;
  if (!schoolId) {
    throw new OnboardingProvisionError("This request has no provisioned school yet");
  }

  let email =
    typeof ob.adminEmail === "string" && ob.adminEmail ? ob.adminEmail : "";
  if (!email) {
    const adminSnap = await db
      .collection("schools").doc(schoolId)
      .collection("users")
      .where("role", "==", "schoolAdmin")
      .limit(1)
      .get();
    email = (adminSnap.docs[0]?.data()?.email as string) || "";
  }
  if (!email) {
    throw new OnboardingProvisionError(
      "No school-admin account found for this school"
    );
  }

  const link = await auth.generatePasswordResetLink(email);

  await logAuditEvent({
    action: "onboarding.adminLink",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "onboarding",
    targetId: onboardingId,
    schoolId,
    after: { email },
  }).catch((e) => {
    console.error("[onboarding] audit log failed for onboarding.adminLink", e);
  });

  return { email, link };
}
