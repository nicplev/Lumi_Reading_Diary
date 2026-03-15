import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import type { School } from "@/lib/types";

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
