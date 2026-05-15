import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import type { School } from "@lumi/types";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

// --- Phase 1 helpers (unchanged) ---

export async function getSchoolCount(): Promise<number> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .where("isActive", "==", true)
    .count()
    .get();
  return snapshot.data().count;
}

export async function getSchools(limit = 50): Promise<School[]> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  })) as School[];
}

// --- Phase 2 helpers ---

export interface SchoolListItem {
  id: string;
  name: string;
  isActive: boolean;
  studentCount: number;
  teacherCount: number;
  parentCount: number;
  subscriptionPlan?: string;
  contactEmail?: string;
  createdAt: string;
}

export async function listSchools(options?: {
  isActive?: boolean;
  limit?: number;
}): Promise<SchoolListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .orderBy("createdAt", "desc");

  if (options?.isActive !== undefined) {
    query = query.where("isActive", "==", options.isActive);
  }
  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      name: data.name,
      isActive: data.isActive ?? true,
      studentCount: data.studentCount ?? 0,
      teacherCount: data.teacherCount ?? 0,
      parentCount: data.parentCount ?? 0,
      subscriptionPlan: data.subscriptionPlan,
      contactEmail: data.contactEmail,
      createdAt: toISO(data.createdAt),
    };
  });
}

export interface SchoolDetail {
  id: string;
  name: string;
  displayName?: string;
  logoUrl?: string;
  primaryColor?: string;
  secondaryColor?: string;
  levelSchema: string;
  customLevels?: string[];
  timezone: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: string;
  createdBy: string;
  studentCount: number;
  teacherCount: number;
  parentCount: number;
  subscriptionPlan?: string;
  subscriptionExpiry?: string;
}

export async function getSchool(
  schoolId: string
): Promise<SchoolDetail | null> {
  const doc = await getAdminDb().collection("schools").doc(schoolId).get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    name: data.name,
    displayName: data.displayName,
    logoUrl: data.logoUrl,
    primaryColor: data.primaryColor,
    secondaryColor: data.secondaryColor,
    levelSchema: data.levelSchema ?? "aToZ",
    customLevels: data.customLevels,
    timezone: data.timezone ?? "Pacific/Auckland",
    address: data.address,
    contactEmail: data.contactEmail,
    contactPhone: data.contactPhone,
    isActive: data.isActive ?? true,
    createdAt: toISO(data.createdAt),
    createdBy: data.createdBy ?? "",
    studentCount: data.studentCount ?? 0,
    teacherCount: data.teacherCount ?? 0,
    parentCount: data.parentCount ?? 0,
    subscriptionPlan: data.subscriptionPlan,
    subscriptionExpiry: toISO(data.subscriptionExpiry) || undefined,
  };
}

export async function updateSchool(
  schoolId: string,
  data: Record<string, unknown>
): Promise<void> {
  await getAdminDb().collection("schools").doc(schoolId).update(data);
}

export async function deactivateSchool(schoolId: string): Promise<void> {
  await getAdminDb().collection("schools").doc(schoolId).update({
    isActive: false,
  });
}

export interface SchoolStats {
  studentCount: number;
  teacherCount: number;
  parentCount: number;
}

export async function getSchoolStats(
  schoolId: string
): Promise<SchoolStats> {
  const schoolRef = getAdminDb().collection("schools").doc(schoolId);

  const [studentsSnap, usersSnap, parentsSnap] = await Promise.all([
    schoolRef
      .collection("students")
      .where("isActive", "==", true)
      .count()
      .get(),
    schoolRef
      .collection("users")
      .where("isActive", "==", true)
      .count()
      .get(),
    schoolRef
      .collection("parents")
      .where("isActive", "==", true)
      .count()
      .get(),
  ]);

  return {
    studentCount: studentsSnap.data().count,
    teacherCount: usersSnap.data().count,
    parentCount: parentsSnap.data().count,
  };
}
