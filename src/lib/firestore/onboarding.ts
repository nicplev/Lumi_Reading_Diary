import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import type { SchoolOnboarding } from "@/lib/types";

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
