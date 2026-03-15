import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

export interface ReadingLogStats {
  thisWeek: number;
  thisMonth: number;
}

export async function getReadingLogStats(): Promise<ReadingLogStats> {
  const now = new Date();
  const startOfWeek = new Date(now);
  startOfWeek.setDate(now.getDate() - now.getDay());
  startOfWeek.setHours(0, 0, 0, 0);

  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  const schools = await getAdminDb().collection("schools").listDocuments();

  let thisWeek = 0;
  let thisMonth = 0;

  await Promise.all(
    schools.map(async (schoolRef) => {
      const weekSnapshot = await schoolRef
        .collection("readingLogs")
        .where("createdAt", ">=", Timestamp.fromDate(startOfWeek))
        .count()
        .get();
      thisWeek += weekSnapshot.data().count;

      const monthSnapshot = await schoolRef
        .collection("readingLogs")
        .where("createdAt", ">=", Timestamp.fromDate(startOfMonth))
        .count()
        .get();
      thisMonth += monthSnapshot.data().count;
    })
  );

  return { thisWeek, thisMonth };
}

export interface RecentActivity {
  id: string;
  schoolId: string;
  studentId: string;
  minutesRead: number;
  status: string;
  bookTitles: string[];
  createdAt: Date;
}

export async function getRecentActivity(
  limit = 10
): Promise<RecentActivity[]> {
  const schools = await getAdminDb().collection("schools").listDocuments();
  const allLogs: RecentActivity[] = [];

  await Promise.all(
    schools.map(async (schoolRef) => {
      const snapshot = await schoolRef
        .collection("readingLogs")
        .orderBy("createdAt", "desc")
        .limit(limit)
        .get();

      for (const doc of snapshot.docs) {
        const data = doc.data();
        allLogs.push({
          id: doc.id,
          schoolId: schoolRef.id,
          studentId: data.studentId,
          minutesRead: data.minutesRead,
          status: data.status,
          bookTitles: data.bookTitles || [],
          createdAt: data.createdAt?.toDate() || new Date(),
        });
      }
    })
  );

  allLogs.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
  return allLogs.slice(0, limit);
}
