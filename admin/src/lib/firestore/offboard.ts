import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";

export interface OffboardPreview {
  schoolName: string;
  users: number;
  students: number;
  parents: number;
  classes: number;
  allocations: number;
  books: number;
  readingLogs: number;
}

export async function getOffboardPreview(
  schoolId: string
): Promise<OffboardPreview | null> {
  const db = getAdminDb();
  const schoolDoc = await db.collection("schools").doc(schoolId).get();
  if (!schoolDoc.exists) return null;

  const schoolName = (schoolDoc.data()?.name as string) ?? schoolId;

  const subcollections = [
    "users",
    "students",
    "parents",
    "classes",
    "allocations",
    "books",
    "readingLogs",
  ] as const;

  const counts = await Promise.all(
    subcollections.map(async (col) => {
      const snap = await db
        .collection("schools")
        .doc(schoolId)
        .collection(col)
        .count()
        .get();
      return snap.data().count;
    })
  );

  return {
    schoolName,
    users: counts[0],
    students: counts[1],
    parents: counts[2],
    classes: counts[3],
    allocations: counts[4],
    books: counts[5],
    readingLogs: counts[6],
  };
}

export async function softDeactivateSubcollection(
  schoolId: string,
  collectionName: string
): Promise<number> {
  const db = getAdminDb();
  const colRef = db
    .collection("schools")
    .doc(schoolId)
    .collection(collectionName);

  const snapshot = await colRef.get();
  if (snapshot.empty) return 0;

  // Batch writes (500 per batch limit)
  const batches: FirebaseFirestore.WriteBatch[] = [];
  let currentBatch = db.batch();
  let operationCount = 0;

  for (const doc of snapshot.docs) {
    currentBatch.update(doc.ref, { isActive: false });
    operationCount += 1;

    if (operationCount % 500 === 0) {
      batches.push(currentBatch);
      currentBatch = db.batch();
    }
  }

  if (operationCount % 500 !== 0) {
    batches.push(currentBatch);
  }

  await Promise.all(batches.map((b) => b.commit()));
  return snapshot.size;
}

export async function softDeactivateSchool(
  schoolId: string
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .update({ isActive: false });
}
