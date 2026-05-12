import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import type { SchoolOnboarding } from "@lumi/types";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

// --- Phase 1 helpers (unchanged) ---

export async function getOnboardingCount(): Promise<number> {
  const snapshot = await getAdminDb()
    .collection("schoolOnboarding")
    .count()
    .get();
  return snapshot.data().count;
}

export async function getRecentOnboardingRequests(
  limit = 5
): Promise<SchoolOnboarding[]> {
  const snapshot = await getAdminDb()
    .collection("schoolOnboarding")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as SchoolOnboarding[];
}

// --- Phase 2 helpers ---

export interface OnboardingListItem {
  id: string;
  schoolName: string;
  contactEmail: string;
  contactPerson?: string;
  status: string;
  currentStep: string;
  completedSteps: string[];
  estimatedStudentCount: number;
  estimatedTeacherCount: number;
  createdAt: string;
  lastUpdatedAt?: string;
  schoolId?: string;
}

export async function listOnboardingRequests(
  status?: string
): Promise<OnboardingListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schoolOnboarding")
    .orderBy("createdAt", "desc");

  if (status) {
    query = query.where("status", "==", status);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      schoolName: data.schoolName,
      contactEmail: data.contactEmail,
      contactPerson: data.contactPerson,
      status: data.status,
      currentStep: data.currentStep,
      completedSteps: data.completedSteps ?? [],
      estimatedStudentCount: data.estimatedStudentCount ?? 0,
      estimatedTeacherCount: data.estimatedTeacherCount ?? 0,
      createdAt: toISO(data.createdAt),
      lastUpdatedAt: toISO(data.lastUpdatedAt) || undefined,
      schoolId: data.schoolId,
    };
  });
}

export interface OnboardingDetail extends OnboardingListItem {
  contactPhone?: string;
  adminUserId?: string;
  demoScheduledAt?: string;
  registrationCompletedAt?: string;
  referralSource?: string;
  metadata?: Record<string, unknown>;
}

export async function getOnboarding(
  id: string
): Promise<OnboardingDetail | null> {
  const doc = await getAdminDb().collection("schoolOnboarding").doc(id).get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    schoolName: data.schoolName,
    contactEmail: data.contactEmail,
    contactPerson: data.contactPerson,
    contactPhone: data.contactPhone,
    status: data.status,
    currentStep: data.currentStep,
    completedSteps: data.completedSteps ?? [],
    estimatedStudentCount: data.estimatedStudentCount ?? 0,
    estimatedTeacherCount: data.estimatedTeacherCount ?? 0,
    createdAt: toISO(data.createdAt),
    lastUpdatedAt: toISO(data.lastUpdatedAt) || undefined,
    schoolId: data.schoolId,
    adminUserId: data.adminUserId,
    demoScheduledAt: toISO(data.demoScheduledAt) || undefined,
    registrationCompletedAt: toISO(data.registrationCompletedAt) || undefined,
    referralSource: data.referralSource,
    metadata: data.metadata,
  };
}

const STEP_ORDER = [
  "schoolInfo",
  "adminAccount",
  "readingLevels",
  "importData",
  "inviteTeachers",
  "completed",
] as const;

export async function updateOnboardingStatus(
  id: string,
  status: string
): Promise<void> {
  await getAdminDb().collection("schoolOnboarding").doc(id).update({
    status,
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });
}

export async function advanceOnboardingStep(id: string): Promise<string> {
  const doc = await getAdminDb().collection("schoolOnboarding").doc(id).get();
  if (!doc.exists) throw new Error("Onboarding request not found");

  const data = doc.data()!;
  const currentStep = data.currentStep as string;
  const currentIndex = STEP_ORDER.indexOf(
    currentStep as (typeof STEP_ORDER)[number]
  );

  if (currentIndex === -1 || currentIndex >= STEP_ORDER.length - 1) {
    throw new Error("Cannot advance: already at final step");
  }

  const nextStep = STEP_ORDER[currentIndex + 1];
  const completedSteps = [
    ...((data.completedSteps as string[]) || []),
    currentStep,
  ];

  await getAdminDb().collection("schoolOnboarding").doc(id).update({
    currentStep: nextStep,
    completedSteps,
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });

  return nextStep;
}

export async function linkOnboardingToSchool(
  id: string,
  schoolId: string
): Promise<void> {
  await getAdminDb().collection("schoolOnboarding").doc(id).update({
    schoolId,
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });
}
