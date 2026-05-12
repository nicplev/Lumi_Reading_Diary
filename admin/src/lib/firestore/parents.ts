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

export interface ParentListItem {
  id: string;
  email: string;
  fullName: string;
  schoolId: string;
  schoolName?: string;
  linkedChildrenCount: number;
  isActive: boolean;
  createdAt: string;
  lastLoginAt?: string;
}

export interface ParentDetail extends ParentListItem {
  linkedChildren: string[];
  profileImageUrl?: string;
  preferences?: Record<string, unknown>;
}

export async function listParents(
  schoolId: string,
  options?: { isActive?: boolean }
): Promise<ParentListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("parents")
    .orderBy("createdAt", "desc");

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
      schoolId,
      linkedChildrenCount: (data.linkedChildren as string[])?.length ?? 0,
      isActive: data.isActive ?? true,
      createdAt: toISO(data.createdAt),
      lastLoginAt: toISO(data.lastLoginAt) || undefined,
    };
  });
}

export async function getParent(
  schoolId: string,
  parentId: string
): Promise<ParentDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("parents")
    .doc(parentId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    email: data.email,
    fullName: data.fullName,
    schoolId,
    linkedChildren: data.linkedChildren ?? [],
    linkedChildrenCount: (data.linkedChildren as string[])?.length ?? 0,
    profileImageUrl: data.profileImageUrl,
    isActive: data.isActive ?? true,
    createdAt: toISO(data.createdAt),
    lastLoginAt: toISO(data.lastLoginAt) || undefined,
    preferences: data.preferences,
  };
}

export async function listAllParents(
  options?: { limit?: number }
): Promise<ParentListItem[]> {
  const schoolsSnap = await getAdminDb().collection("schools").get();

  const allParents = await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolData = schoolDoc.data();
      const parentsSnap = await schoolDoc.ref
        .collection("parents")
        .orderBy("createdAt", "desc")
        .get();

      return parentsSnap.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          email: data.email,
          fullName: data.fullName,
          schoolId: schoolDoc.id,
          schoolName: schoolData.name as string,
          linkedChildrenCount: (data.linkedChildren as string[])?.length ?? 0,
          isActive: data.isActive ?? true,
          createdAt: toISO(data.createdAt),
          lastLoginAt: toISO(data.lastLoginAt) || undefined,
        };
      });
    })
  );

  const flat = allParents
    .flat()
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  if (options?.limit) return flat.slice(0, options.limit);
  return flat;
}
