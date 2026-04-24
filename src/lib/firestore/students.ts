import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

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

// --- Phase 1 helpers (unchanged) ---

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

// --- Phase 3 helpers ---

export interface StudentListItem {
  id: string;
  firstName: string;
  lastName: string;
  studentId?: string;
  schoolId: string;
  schoolName?: string;
  classId: string;
  currentReadingLevel?: string;
  parentLinked: boolean;
  isActive: boolean;
  createdAt: string;
}

export interface StudentDetail extends StudentListItem {
  currentReadingLevelIndex?: number;
  readingLevelUpdatedAt?: string;
  readingLevelUpdatedBy?: string;
  readingLevelSource?: string;
  parentIds: string[];
  dateOfBirth?: string;
  profileImageUrl?: string;
  enrolledAt?: string;
  stats?: {
    totalMinutesRead: number;
    totalBooksRead: number;
    currentStreak: number;
    longestStreak: number;
    lastReadingDate?: string;
    averageMinutesPerDay: number;
    totalReadingDays: number;
  };
}

export async function listStudents(
  schoolId: string,
  options?: { classId?: string; isActive?: boolean }
): Promise<StudentListItem[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .orderBy("createdAt", "desc");

  if (options?.classId) {
    query = query.where("classId", "==", options.classId);
  }
  if (options?.isActive !== undefined) {
    query = query.where("isActive", "==", options.isActive);
  }

  const snapshot = await query.get();
  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      firstName: data.firstName,
      lastName: data.lastName,
      studentId: data.studentId,
      schoolId,
      classId: data.classId,
      currentReadingLevel: data.currentReadingLevel,
      parentLinked: ((data.parentIds as string[]) ?? []).length > 0,
      isActive: data.isActive ?? true,
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function getStudent(
  schoolId: string,
  studentId: string
): Promise<StudentDetail | null> {
  const doc = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .doc(studentId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data()!;
  const stats = data.stats
    ? {
        totalMinutesRead: data.stats.totalMinutesRead ?? 0,
        totalBooksRead: data.stats.totalBooksRead ?? 0,
        currentStreak: data.stats.currentStreak ?? 0,
        longestStreak: data.stats.longestStreak ?? 0,
        lastReadingDate: toISO(data.stats.lastReadingDate) || undefined,
        averageMinutesPerDay: data.stats.averageMinutesPerDay ?? 0,
        totalReadingDays: data.stats.totalReadingDays ?? 0,
      }
    : undefined;

  return {
    id: doc.id,
    firstName: data.firstName,
    lastName: data.lastName,
    studentId: data.studentId,
    schoolId,
    classId: data.classId,
    currentReadingLevel: data.currentReadingLevel,
    currentReadingLevelIndex: data.currentReadingLevelIndex,
    readingLevelUpdatedAt: toISO(data.readingLevelUpdatedAt) || undefined,
    readingLevelUpdatedBy: data.readingLevelUpdatedBy,
    readingLevelSource: data.readingLevelSource,
    parentIds: data.parentIds ?? [],
    parentLinked: ((data.parentIds as string[]) ?? []).length > 0,
    dateOfBirth: toISO(data.dateOfBirth) || undefined,
    profileImageUrl: data.profileImageUrl,
    isActive: data.isActive ?? true,
    createdAt: toISO(data.createdAt),
    enrolledAt: toISO(data.enrolledAt) || undefined,
    stats,
  };
}

export async function createStudent(
  schoolId: string,
  data: {
    firstName: string;
    lastName: string;
    studentId?: string;
    classId: string;
    currentReadingLevel?: string;
  }
): Promise<string> {
  const docRef = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .add({
      firstName: data.firstName,
      lastName: data.lastName,
      studentId: data.studentId || null,
      classId: data.classId,
      currentReadingLevel: data.currentReadingLevel || null,
      parentIds: [],
      levelHistory: [],
      isActive: true,
      createdAt: FieldValue.serverTimestamp(),
    });
  return docRef.id;
}

export async function updateStudent(
  schoolId: string,
  studentId: string,
  data: Record<string, unknown>
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .doc(studentId)
    .update(data);
}

export async function deactivateStudent(
  schoolId: string,
  studentId: string
): Promise<void> {
  await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .doc(studentId)
    .update({ isActive: false });
}

export interface ReadingLevelEventItem {
  id: string;
  fromLevel?: string;
  toLevel?: string;
  fromLevelIndex?: number;
  toLevelIndex?: number;
  reason?: string;
  source: string;
  changedByUserId: string;
  changedByName: string;
  createdAt: string;
}

export async function getReadingLevelEvents(
  schoolId: string,
  studentId: string,
  limit = 50
): Promise<ReadingLevelEventItem[]> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .doc(studentId)
    .collection("readingLevelEvents")
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      fromLevel: data.fromLevel,
      toLevel: data.toLevel,
      fromLevelIndex: data.fromLevelIndex,
      toLevelIndex: data.toLevelIndex,
      reason: data.reason,
      source: data.source ?? "admin",
      changedByUserId: data.changedByUserId ?? "",
      changedByName: data.changedByName ?? "",
      createdAt: toISO(data.createdAt),
    };
  });
}

export async function updateReadingLevel(
  schoolId: string,
  studentId: string,
  data: {
    level: string;
    levelIndex?: number;
    reason?: string;
    source?: string;
    changedByUserId: string;
    changedByName: string;
  }
): Promise<void> {
  const db = getAdminDb();
  const studentRef = db
    .collection("schools")
    .doc(schoolId)
    .collection("students")
    .doc(studentId);

  const studentDoc = await studentRef.get();
  if (!studentDoc.exists) throw new Error("Student not found");

  const studentData = studentDoc.data()!;

  await studentRef.update({
    currentReadingLevel: data.level,
    currentReadingLevelIndex: data.levelIndex ?? null,
    readingLevelUpdatedAt: FieldValue.serverTimestamp(),
    readingLevelUpdatedBy: data.changedByUserId,
    readingLevelSource: data.source ?? "admin",
  });

  await studentRef.collection("readingLevelEvents").add({
    studentId,
    schoolId,
    classId: studentData.classId,
    fromLevel: studentData.currentReadingLevel || null,
    toLevel: data.level,
    fromLevelIndex: studentData.currentReadingLevelIndex ?? null,
    toLevelIndex: data.levelIndex ?? null,
    reason: data.reason || null,
    source: data.source ?? "admin",
    changedByUserId: data.changedByUserId,
    changedByRole: "admin",
    changedByName: data.changedByName,
    createdAt: FieldValue.serverTimestamp(),
  });
}

export async function listAllStudents(
  options?: { limit?: number }
): Promise<StudentListItem[]> {
  const schoolsSnap = await getAdminDb().collection("schools").get();

  const allStudents = await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolData = schoolDoc.data();
      const studentsSnap = await schoolDoc.ref
        .collection("students")
        .orderBy("createdAt", "desc")
        .get();

      return studentsSnap.docs.map((doc) => {
        const data = doc.data();
        return {
          id: doc.id,
          firstName: data.firstName,
          lastName: data.lastName,
          studentId: data.studentId,
          schoolId: schoolDoc.id,
          schoolName: schoolData.name as string,
          classId: data.classId,
          currentReadingLevel: data.currentReadingLevel,
          parentLinked: ((data.parentIds as string[]) ?? []).length > 0,
          isActive: data.isActive ?? true,
          createdAt: toISO(data.createdAt),
        };
      });
    })
  );

  const flat = allStudents
    .flat()
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  if (options?.limit) return flat.slice(0, options.limit);
  return flat;
}
