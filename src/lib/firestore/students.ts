import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

export async function getStudentCount(): Promise<number> {
  const schools = await getAdminDb().collection("schools").listDocuments();
  let total = 0;

  const counts = await Promise.all(
    schools.map(async (schoolRef) => {
      const snapshot = await schoolRef
        .collection("students")
        .where("isActive", "==", true)
        .count()
        .get();
      return snapshot.data().count;
    })
  );

  for (const count of counts) {
    total += count;
  }

  return total;
}
