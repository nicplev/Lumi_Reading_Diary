import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

export interface SchoolUserListItem {
  id: string;
  email: string;
  fullName: string;
  role: string;
  schoolId: string;
  schoolName?: string;
  classIds: string[];
  isActive: boolean;
  createdAt: string;
  lastLoginAt?: string;
}

export interface SchoolUserDetail extends SchoolUserListItem {
  linkedChildren: string[];
  profileImageUrl?: string;
  preferences?: Record<string, unknown>;
}

export async function listSchoolUsers(
  schoolId: string,
  options?: { role?: string; isActive?: boolean }
): Promise<SchoolUserListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("users")
    .orderBy("createdAt", "desc");

  if (options?.role) {
    query = query.where("role", "==", options.role);
  }
  if (options?.isActive !== undefined) {
    query = query.where("isActive", "==", options.isActive);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      email: data.email,
      fullName: data.fullName,
      role: data.role,
      schoolId,
      classIds: data.classIds ?? [],
      isActive: data.isActive ?? true,
      createdAt: toISO(data.createdAt),
      lastLoginAt: toISO(data.lastLoginAt) || undefined,
    };
  });
}

export async function getSchoolUser(
  schoolId: string,
  userId: string
): Promise<SchoolUserDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("users")
    .doc(userId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    email: data.email,
    fullName: data.fullName,
    role: data.role,
    schoolId,
    classIds: data.classIds ?? [],
    linkedChildren: data.linkedChildren ?? [],
    profileImageUrl: data.profileImageUrl,
    isActive: data.isActive ?? true,
    createdAt: toISO(data.createdAt),
    lastLoginAt: toISO(data.lastLoginAt) || undefined,
    preferences: data.preferences,
  };
}

export async function updateSchoolUser(
  schoolId: string,
  userId: string,
  data: Record<string, unknown>
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("users")
    .doc(userId)
    .update(data);
}

export async function deactivateSchoolUser(
  schoolId: string,
  userId: string
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("users")
    .doc(userId)
    .update({ isActive: false });
}

export async function listAllUsers(
  options?: { limit?: number }
): Promise<SchoolUserListItem[]> {
  const schoolsSnap = await getAdminDb().collection("schools").get();

  const allUsers = await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolData = schoolDoc.data();
      const usersSnap = await schoolDoc.ref
        .collection("users")
        .orderBy("createdAt", "desc")
        .get();

      return usersSnap.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          email: data.email,
          fullName: data.fullName,
          role: data.role,
          schoolId: schoolDoc.id,
          schoolName: schoolData.name as string,
          classIds: data.classIds ?? [],
          isActive: data.isActive ?? true,
          createdAt: toISO(data.createdAt),
          lastLoginAt: toISO(data.lastLoginAt) || undefined,
        };
      });
    })
  );

  const flat = allUsers
    .flat()
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  if (options?.limit) return flat.slice(0, options.limit);
  return flat;
}
