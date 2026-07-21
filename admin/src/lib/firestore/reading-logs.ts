import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

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
        if (data.validationStatus === "invalid") continue;
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

// --- Phase 4 helpers ---

export interface ReadingLogListItem {
  id: string;
  studentId: string;
  parentId?: string;
  schoolId: string;
  classId?: string;
  date: string;
  minutesRead: number;
  targetMinutes?: number;
  status: string;
  bookTitles: string[];
  childFeeling?: string;
  isOfflineCreated: boolean;
  hasTeacherComment: boolean;
  hasParentComment: boolean;
  createdAt: string;
}

export interface ReadingLogDetail extends ReadingLogListItem {
  notes?: string;
  photoUrls: string[];
  syncedAt?: string;
  allocationId?: string;
  parentComment?: string;
  parentCommentSelections: string[];
  parentCommentFreeText?: string;
  teacherComment?: string;
  commentedAt?: string;
  commentedBy?: string;
  metadata?: Record<string, unknown>;
}

export async function listReadingLogs(
  schoolId: string,
  options?: {
    classId?: string;
    studentId?: string;
    status?: string;
    startDate?: string;
    endDate?: string;
    limit?: number;
  }
): Promise<ReadingLogListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("readingLogs")
    .orderBy("date", "desc");

  // Default to last 7 days when no dates given
  if (!options?.startDate && !options?.endDate) {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
    sevenDaysAgo.setHours(0, 0, 0, 0);
    query = query.where("date", ">=", Timestamp.fromDate(sevenDaysAgo));
  } else {
    if (options?.startDate) {
      query = query.where(
        "date",
        ">=",
        Timestamp.fromDate(new Date(options.startDate))
      );
    }
    if (options?.endDate) {
      const endDate = new Date(options.endDate);
      endDate.setHours(23, 59, 59, 999);
      query = query.where("date", "<=", Timestamp.fromDate(endDate));
    }
  }

  if (options?.limit) {
    query = query.limit(options.limit);
  }

  const snapshot = await query.get();
  let results = snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      studentId: data.studentId,
      parentId: data.parentId,
      schoolId,
      classId: data.classId,
      date: toISO(data.date),
      minutesRead: data.minutesRead ?? 0,
      targetMinutes: data.targetMinutes,
      status: data.status ?? "pending",
      bookTitles: (data.bookTitles as string[]) ?? [],
      childFeeling: data.readingFeeling,
      isOfflineCreated: data.isOfflineCreated ?? false,
      hasTeacherComment: !!data.teacherComment,
      hasParentComment: !!data.parentComment,
      createdAt: toISO(data.createdAt),
    };
  });

  // Client-side filters for fields that can't combine with Firestore range queries
  if (options?.classId) {
    results = results.filter((r) => r.classId === options.classId);
  }
  if (options?.studentId) {
    results = results.filter((r) => r.studentId === options.studentId);
  }
  if (options?.status) {
    results = results.filter((r) => r.status === options.status);
  }

  return results;
}

export async function getReadingLog(
  schoolId: string,
  logId: string
): Promise<ReadingLogDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("readingLogs")
    .doc(logId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  return {
    id: doc.id,
    studentId: data.studentId,
    parentId: data.parentId,
    schoolId,
    classId: data.classId,
    date: toISO(data.date),
    minutesRead: data.minutesRead ?? 0,
    targetMinutes: data.targetMinutes,
    status: data.status ?? "pending",
    bookTitles: (data.bookTitles as string[]) ?? [],
    childFeeling: data.readingFeeling,
    isOfflineCreated: data.isOfflineCreated ?? false,
    hasTeacherComment: !!data.teacherComment,
    hasParentComment: !!data.parentComment,
    notes: data.notes,
    photoUrls: (data.photoUrls as string[]) ?? [],
    syncedAt: toISO(data.syncedAt) || undefined,
    allocationId: data.allocationId,
    parentComment: data.parentComment,
    parentCommentSelections: (data.parentCommentSelections as string[]) ?? [],
    parentCommentFreeText: data.parentCommentFreeText,
    teacherComment: data.teacherComment,
    commentedAt: toISO(data.commentedAt) || undefined,
    commentedBy: data.commentedBy,
    metadata: data.metadata,
    createdAt: toISO(data.createdAt),
  };
}

export async function getReadingLogCountForSchool(
  schoolId: string,
  sinceDays = 7
): Promise<number> {
  const since = new Date();
  since.setDate(since.getDate() - sinceDays);
  since.setHours(0, 0, 0, 0);

  const snapshot = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("readingLogs")
    .where("date", ">=", Timestamp.fromDate(since))
    .count()
    .get();
  return snapshot.data().count;
}

export interface GlobalReadingLogItem {
  id: string;
  schoolId: string;
  schoolName?: string;
  studentId: string;
  studentName?: string;
  minutesRead: number;
  status: string;
  bookTitles: string[];
  date: string;
  createdAt: string;
  validationStatus?: string;
  validationErrors: string[];
  validationReviewStatus: "open" | "acknowledged";
}

export async function listAllReadingLogs(
  options?: {
    limit?: number;
    validation?: "invalid";
    review?: "open" | "all";
    period?: "today" | "7d";
  }
): Promise<GlobalReadingLogItem[]> {
  const db = getAdminDb();
  const sevenDaysAgo = new Date(Date.now() - 7 * 86_400_000);
  const sydneyDate = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Australia/Sydney",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const today = sydneyDate.format(new Date());

  const schoolsSnap = await db.collection("schools").get();
  const allLogs: GlobalReadingLogItem[] = [];

  await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolName = (schoolDoc.data().name as string) ?? "";
      let query: FirebaseFirestore.Query = schoolDoc.ref.collection("readingLogs");
      if (options?.validation === "invalid") {
        query = query.where("validationStatus", "==", "invalid");
      } else {
        query = query
          .where("createdAt", ">=", Timestamp.fromDate(sevenDaysAgo))
          .orderBy("createdAt", "desc");
      }
      const snapshot = await query.limit(options?.limit ?? 200).get();

      const periodDocs = snapshot.docs.filter((doc) => {
        if (!options?.validation && doc.data().validationStatus === "invalid") {
          return false;
        }
        if (options?.validation || options?.period !== "today") return true;
        const createdAt = doc.data().createdAt?.toDate?.() as Date | undefined;
        return createdAt ? sydneyDate.format(createdAt) === today : false;
      });
      const visibleDocs = periodDocs.filter((doc) => {
        if (options?.review !== "open") return true;
        return doc.data().validationReviewStatus !== "acknowledged";
      });
      const studentIds = [
        ...new Set(
          visibleDocs
            .map((doc) => doc.data().studentId)
            .filter(
              (id): id is string =>
                typeof id === "string" &&
                id.length > 0 &&
                id.length <= 256 &&
                !id.includes("/")
            )
        ),
      ];
      const studentDocs = studentIds.length
        ? await db.getAll(
            ...studentIds.map((id) => schoolDoc.ref.collection("students").doc(id))
          )
        : [];
      const studentNames = new Map(
        studentDocs.map((doc) => {
          const student = doc.data() ?? {};
          const name = `${student.firstName ?? ""} ${student.lastName ?? ""}`.trim();
          return [doc.id, name] as const;
        })
      );

      for (const doc of visibleDocs) {
        const data = doc.data();
        const studentId =
          typeof data.studentId === "string" ? data.studentId : "";
        allLogs.push({
          id: doc.id,
          schoolId: schoolDoc.id,
          schoolName,
          studentId,
          studentName: studentNames.get(studentId),
          minutesRead: data.minutesRead ?? 0,
          status: data.status ?? "pending",
          bookTitles: (data.bookTitles as string[]) ?? [],
          date: toISO(data.date),
          createdAt: toISO(data.createdAt),
          validationStatus: data.validationStatus,
          validationErrors: Array.isArray(data.validationErrors)
            ? data.validationErrors.filter(
                (error: unknown): error is string => typeof error === "string"
              )
            : [],
          validationReviewStatus:
            data.validationReviewStatus === "acknowledged"
              ? "acknowledged"
              : "open",
        });
      }
    })
  );

  allLogs.sort((a, b) => b.date.localeCompare(a.date));
  if (options?.limit) return allLogs.slice(0, options.limit);
  return allLogs;
}
