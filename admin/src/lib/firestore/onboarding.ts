import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { type SchoolOnboarding, isActiveSubscriptionStatus } from "@lumi/types";
import {
  getCurrentAcademicYear,
  getSubscriptionsForSchool,
} from "./school-subscriptions";
import { provisionUnprovisionedStudents } from "./access-grants";
import type { CreateOnboardingInput } from "@/lib/validations/onboarding";

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

// --- Intake (create / delete) ---

// Writes the same doc shape the Flutter inbound demo-request form does, so
// operator-created (outbound) leads and inbound leads live in one pipeline.
export async function createOnboardingRequest(
  data: CreateOnboardingInput
): Promise<string> {
  const now = FieldValue.serverTimestamp();
  const doc: Record<string, unknown> = {
    schoolName: data.schoolName,
    contactEmail: data.contactEmail,
    contactPerson: data.contactPerson ?? null,
    contactPhone: data.contactPhone ?? null,
    status: data.status ?? "demo",
    currentStep: "schoolInfo",
    completedSteps: [],
    estimatedStudentCount: data.estimatedStudentCount ?? 0,
    estimatedTeacherCount: data.estimatedTeacherCount ?? 0,
    referralSource: data.referralSource ?? null,
    createdAt: now,
    lastUpdatedAt: now,
  };
  if (data.notes) doc.metadata = { notes: data.notes };
  const ref = await getAdminDb().collection("schoolOnboarding").add(doc);
  return ref.id;
}

export async function deleteOnboardingRequest(id: string): Promise<void> {
  await getAdminDb().collection("schoolOnboarding").doc(id).delete();
}

// --- Follow-up / CRM edit ---

export interface UpdateOnboardingDetailsPatch {
  contactPerson?: string;
  contactEmail?: string;
  contactPhone?: string;
  estimatedStudentCount?: number;
  estimatedTeacherCount?: number;
  referralSource?: string;
  demoScheduledAt?: string; // ISO; "" clears
  nextStepAt?: string; // ISO; "" clears (metadata)
  nextStepNote?: string; // metadata
  notes?: string; // metadata
}

export async function updateOnboardingDetails(
  id: string,
  patch: UpdateOnboardingDetailsPatch
): Promise<void> {
  const update: Record<string, unknown> = {
    lastUpdatedAt: FieldValue.serverTimestamp(),
  };

  const topLevel: (keyof UpdateOnboardingDetailsPatch)[] = [
    "contactPerson",
    "contactEmail",
    "contactPhone",
    "estimatedStudentCount",
    "estimatedTeacherCount",
    "referralSource",
  ];
  for (const k of topLevel) {
    if (patch[k] !== undefined) update[k] = patch[k];
  }

  if (patch.demoScheduledAt !== undefined) {
    update.demoScheduledAt = patch.demoScheduledAt
      ? Timestamp.fromDate(new Date(patch.demoScheduledAt))
      : FieldValue.delete();
  }
  // Follow-up cadence lives in the existing `metadata` map (no shared-type
  // change). Dotted paths patch individual keys without clobbering the map.
  for (const k of ["nextStepAt", "nextStepNote", "notes"] as const) {
    if (patch[k] !== undefined) update[`metadata.${k}`] = patch[k];
  }

  await getAdminDb().collection("schoolOnboarding").doc(id).update(update);
}

// --- Readiness + gated go-live ---

export type ReadinessStatus = "ok" | "warn" | "fail" | "na";

export interface ReadinessItem {
  key: string;
  label: string;
  status: ReadinessStatus;
  detail: string;
  blocking: boolean;
  /** Optional in-portal deep link to fix the gap. */
  fixHref?: string;
}

export interface OnboardingReadiness {
  linked: boolean;
  schoolId?: string;
  items: ReadinessItem[];
  canGoLive: boolean;
}

// Live, fail-closed readiness for a linked school. Blocking items (school +
// active subscription + materialised access) gate Go-Live; the rest are
// warnings the operator can override. The night-one landmine — students with
// no `access` map — is surfaced explicitly (Go-Live grants them).
export async function getOnboardingReadiness(
  id: string
): Promise<OnboardingReadiness> {
  const db = getAdminDb();
  const ob = await db.collection("schoolOnboarding").doc(id).get();
  const schoolId = ob.data()?.schoolId as string | undefined;

  if (!schoolId) {
    return {
      linked: false,
      items: [
        {
          key: "schoolLinked",
          label: "School provisioned",
          status: "fail",
          detail: "No school linked yet — provision first.",
          blocking: true,
        },
      ],
      canGoLive: false,
    };
  }

  const schoolRef = db.collection("schools").doc(schoolId);
  const [schoolSnap, subs, year] = await Promise.all([
    schoolRef.get(),
    getSubscriptionsForSchool(schoolId),
    getCurrentAcademicYear(),
  ]);
  const school = (schoolSnap.data() ?? {}) as Record<string, unknown>;
  const access = school.access as { status?: string } | undefined;
  const schoolTab = `/schools/${schoolId}`;
  const items: ReadinessItem[] = [];

  items.push({
    key: "schoolLinked",
    label: "School provisioned",
    status: schoolSnap.exists ? "ok" : "fail",
    detail: schoolSnap.exists
      ? (school.name as string) || schoolId
      : "Linked school not found",
    blocking: true,
    fixHref: schoolTab,
  });

  const curSub = subs.find((s) => s.academicYear === year);
  const subActive = curSub ? isActiveSubscriptionStatus(curSub.status) : false;
  items.push({
    key: "subscriptionActive",
    label: `Subscription active (${year})`,
    status: subActive ? "ok" : "fail",
    detail: curSub ? `status: ${curSub.status}` : "no subscription row",
    blocking: true,
    fixHref: `${schoolTab}?tab=subscription`,
  });

  items.push({
    key: "schoolAccessActive",
    label: "School access active",
    status: access?.status === "active" ? "ok" : "fail",
    detail: access?.status ? `access: ${access.status}` : "no access map",
    blocking: true,
    fixHref: `${schoolTab}?tab=subscription`,
  });

  items.push({
    key: "timezone",
    label: "Timezone set",
    status: school.timezone ? "ok" : "warn",
    detail: (school.timezone as string) || "not set",
    blocking: false,
    fixHref: `${schoolTab}?tab=settings`,
  });

  const termDates = school.termDates as Record<string, unknown> | undefined;
  const hasTerm = !!termDates && Object.keys(termDates).length > 0;
  items.push({
    key: "termDates",
    label: "Term dates set",
    status: hasTerm ? "ok" : "warn",
    detail: hasTerm ? "configured" : "not set — streaks/analytics degraded",
    blocking: false,
    fixHref: `${schoolTab}?tab=settings`,
  });

  const [classesCount, usersCount, studentsSnap] = await Promise.all([
    schoolRef.collection("classes").count().get(),
    schoolRef.collection("users").count().get(),
    schoolRef.collection("students").where("isActive", "==", true).get(),
  ]);
  const nClasses = classesCount.data().count;
  const nStaff = usersCount.data().count;
  const activeStudents = studentsSnap.docs;
  const nStudents = activeStudents.length;

  items.push({
    key: "hasClass",
    label: "At least one class",
    status: nClasses > 0 ? "ok" : "warn",
    detail: `${nClasses} class(es)`,
    blocking: false,
    fixHref: `${schoolTab}?tab=classes`,
  });
  items.push({
    key: "hasTeacher",
    label: "At least one teacher/admin",
    status: nStaff > 0 ? "ok" : "warn",
    detail: `${nStaff} user(s)`,
    blocking: false,
    fixHref: `${schoolTab}?tab=users`,
  });
  items.push({
    key: "hasStudent",
    label: "Students imported",
    status: nStudents > 0 ? "ok" : "warn",
    detail: `${nStudents} active student(s)`,
    blocking: false,
    fixHref: `${schoolTab}?tab=students`,
  });

  const unprovisioned = activeStudents.filter(
    (d) => d.data().access == null
  ).length;
  items.push({
    key: "studentsHaveAccess",
    label: "Students can log reading",
    status:
      nStudents === 0 ? "na" : unprovisioned === 0 ? "ok" : "warn",
    detail:
      nStudents === 0
        ? "no students yet"
        : unprovisioned === 0
          ? "all provisioned"
          : `${unprovisioned} without access — Go Live will grant them`,
    blocking: false,
    fixHref: `${schoolTab}?tab=subscription`,
  });

  const canGoLive = items
    .filter((i) => i.blocking)
    .every((i) => i.status === "ok");

  return { linked: true, schoolId, items, canGoLive };
}

// Thrown when Go-Live is attempted before the blocking readiness items pass.
export class OnboardingBlockedError extends Error {
  blockers: string[];
  constructor(blockers: string[]) {
    super(`Not ready to go live: ${blockers.join(", ")}`);
    this.name = "OnboardingBlockedError";
    this.blockers = blockers;
  }
}

// Flip a request to Active — but first grant access to any imported-but-
// unprovisioned students, so no family is locked out on night one.
export async function goLiveOnboarding(
  id: string,
  actorUid: string
): Promise<{ provisioned: number }> {
  const readiness = await getOnboardingReadiness(id);
  const blockers = readiness.items
    .filter((i) => i.blocking && i.status !== "ok")
    .map((i) => i.label);
  if (blockers.length > 0) {
    throw new OnboardingBlockedError(blockers);
  }

  const schoolId = readiness.schoolId!;
  const year = await getCurrentAcademicYear();
  let provisioned = 0;
  try {
    provisioned = await provisionUnprovisionedStudents(schoolId, year, actorUid);
  } catch (e) {
    // Non-fatal: the school is already active; a straggler-grant hiccup
    // shouldn't block go-live (re-activating the subscription retries it).
    console.error("[onboarding] go-live student provisioning failed", e);
  }

  await getAdminDb().collection("schoolOnboarding").doc(id).update({
    status: "active",
    currentStep: "completed",
    completedSteps: FieldValue.arrayUnion(
      "importData",
      "inviteTeachers",
      "completed"
    ),
    registrationCompletedAt: FieldValue.serverTimestamp(),
    lastUpdatedAt: FieldValue.serverTimestamp(),
  });

  return { provisioned };
}
