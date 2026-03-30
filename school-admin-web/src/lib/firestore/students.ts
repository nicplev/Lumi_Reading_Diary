import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { Student } from '@/lib/types';

function toStudent(doc: FirebaseFirestore.DocumentSnapshot): Student {
  const data = doc.data()!;
  return {
    id: doc.id,
    firstName: data.firstName ?? '',
    lastName: data.lastName ?? '',
    studentId: data.studentId,
    schoolId: data.schoolId ?? '',
    classId: data.classId ?? '',
    currentReadingLevel: data.currentReadingLevel,
    currentReadingLevelIndex: data.currentReadingLevelIndex,
    readingLevelUpdatedAt: data.readingLevelUpdatedAt?.toDate(),
    readingLevelUpdatedBy: data.readingLevelUpdatedBy,
    readingLevelSource: data.readingLevelSource,
    parentIds: data.parentIds ?? [],
    dateOfBirth: data.dateOfBirth?.toDate(),
    profileImageUrl: data.profileImageUrl,
    isActive: data.isActive ?? true,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    enrolledAt: data.enrolledAt?.toDate(),
    additionalInfo: data.additionalInfo,
    levelHistory: (data.levelHistory ?? []).map((lh: Record<string, unknown>) => ({
      level: lh.level as string,
      changedAt: (lh.changedAt as { toDate: () => Date })?.toDate?.() ?? new Date(),
      changedBy: lh.changedBy as string,
      reason: lh.reason as string | undefined,
    })),
    stats: data.stats
      ? {
          totalMinutesRead: data.stats.totalMinutesRead ?? 0,
          totalBooksRead: data.stats.totalBooksRead ?? 0,
          currentStreak: data.stats.currentStreak ?? 0,
          longestStreak: data.stats.longestStreak ?? 0,
          lastReadingDate: data.stats.lastReadingDate?.toDate(),
          averageMinutesPerDay: data.stats.averageMinutesPerDay ?? 0,
          totalReadingDays: data.stats.totalReadingDays ?? 0,
        }
      : undefined,
  };
}

export async function getStudents(
  schoolId: string,
  filters?: { classId?: string; isActive?: boolean }
): Promise<Student[]> {
  let query: FirebaseFirestore.Query = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students');

  if (filters?.classId) {
    query = query.where('classId', '==', filters.classId);
  }

  const isActive = filters?.isActive ?? true;
  query = query.where('isActive', '==', isActive);

  const snap = await query.get();
  return snap.docs.map(toStudent);
}

export async function getStudentsByClass(schoolId: string, classId: string): Promise<Student[]> {
  return getStudents(schoolId, { classId });
}

export async function getStudent(schoolId: string, studentId: string): Promise<Student | null> {
  const doc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId)
    .get();
  if (!doc.exists) return null;
  return toStudent(doc);
}

export async function createStudent(
  schoolId: string,
  data: {
    studentId?: string;
    firstName: string;
    lastName: string;
    classId: string;
    dateOfBirth?: string;
    currentReadingLevel?: string;
    createdBy: string;
  }
): Promise<string> {
  // Check studentId uniqueness if provided
  if (data.studentId) {
    const existing = await adminDb
      .collection('schools')
      .doc(schoolId)
      .collection('students')
      .where('studentId', '==', data.studentId)
      .where('isActive', '==', true)
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new Error(`Student ID "${data.studentId}" is already in use`);
    }
  }

  const ref = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .add({
      ...data,
      schoolId,
      dateOfBirth: data.dateOfBirth ? new Date(data.dateOfBirth) : null,
      parentIds: [],
      isActive: true,
      createdAt: new Date(),
      enrolledAt: new Date(),
      levelHistory: [],
      stats: {
        totalMinutesRead: 0,
        totalBooksRead: 0,
        currentStreak: 0,
        longestStreak: 0,
        averageMinutesPerDay: 0,
        totalReadingDays: 0,
      },
    });

  // Add student to class.studentIds and increment school.studentCount
  const batch = adminDb.batch();
  batch.update(
    adminDb.collection('schools').doc(schoolId).collection('classes').doc(data.classId),
    { studentIds: FieldValue.arrayUnion(ref.id) }
  );
  batch.update(adminDb.collection('schools').doc(schoolId), {
    studentCount: FieldValue.increment(1),
  });
  await batch.commit();

  return ref.id;
}

export async function updateStudent(
  schoolId: string,
  studentId: string,
  data: Partial<Pick<Student, 'firstName' | 'lastName' | 'studentId' | 'classId' | 'currentReadingLevel'>>
): Promise<void> {
  await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId)
    .update(data);
}

export async function deactivateStudent(schoolId: string, studentId: string): Promise<void> {
  const studentDoc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId)
    .get();

  if (!studentDoc.exists) throw new Error('Student not found');
  const classId = studentDoc.data()!.classId;

  const batch = adminDb.batch();
  batch.update(studentDoc.ref, { isActive: false });

  if (classId) {
    batch.update(
      adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId),
      { studentIds: FieldValue.arrayRemove(studentId) }
    );
  }

  batch.update(adminDb.collection('schools').doc(schoolId), {
    studentCount: FieldValue.increment(-1),
  });

  await batch.commit();
}

export interface CSVRow {
  studentId?: string;
  firstName: string;
  lastName: string;
  className: string;
  dateOfBirth?: string;
  parentEmail?: string;
  readingLevel?: string;
}

export interface ImportResult {
  successCount: number;
  errorCount: number;
  errors: { row: number; message: string }[];
  createdClassNames: string[];
}

export async function importStudents(
  schoolId: string,
  rows: CSVRow[],
  createdBy: string
): Promise<ImportResult> {
  const result: ImportResult = { successCount: 0, errorCount: 0, errors: [], createdClassNames: [] };

  // Pre-fetch existing classes
  const classesSnap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('classes')
    .where('isActive', '==', true)
    .get();

  const classMap = new Map<string, string>(); // name → id
  classesSnap.docs.forEach((doc) => {
    classMap.set(doc.data().name?.toLowerCase(), doc.id);
  });

  // Process in batches of 400
  const BATCH_SIZE = 400;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const chunk = rows.slice(i, i + BATCH_SIZE);
    const batch = adminDb.batch();
    let studentCountDelta = 0;

    for (let j = 0; j < chunk.length; j++) {
      const row = chunk[j];
      const rowIndex = i + j + 1;

      if (!row.firstName || !row.lastName || !row.className) {
        result.errors.push({ row: rowIndex, message: 'Missing required fields (firstName, lastName, className)' });
        result.errorCount++;
        continue;
      }

      // Find or create class
      let classId = classMap.get(row.className.toLowerCase());
      if (!classId) {
        const classRef = adminDb
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .doc();
        classId = classRef.id;
        batch.set(classRef, {
          name: row.className,
          schoolId,
          teacherIds: [],
          studentIds: [],
          defaultMinutesTarget: 15,
          isActive: true,
          createdAt: new Date(),
          createdBy,
        });
        classMap.set(row.className.toLowerCase(), classId);
        result.createdClassNames.push(row.className);
      }

      const studentRef = adminDb
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc();

      batch.set(studentRef, {
        studentId: row.studentId || null,
        firstName: row.firstName,
        lastName: row.lastName,
        classId,
        schoolId,
        dateOfBirth: row.dateOfBirth ? new Date(row.dateOfBirth) : null,
        currentReadingLevel: row.readingLevel || null,
        parentIds: [],
        isActive: true,
        createdAt: new Date(),
        enrolledAt: new Date(),
        createdBy,
        levelHistory: [],
        stats: {
          totalMinutesRead: 0,
          totalBooksRead: 0,
          currentStreak: 0,
          longestStreak: 0,
          averageMinutesPerDay: 0,
          totalReadingDays: 0,
        },
      });

      // Add student to class
      batch.update(
        adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId),
        { studentIds: FieldValue.arrayUnion(studentRef.id) }
      );

      studentCountDelta++;
      result.successCount++;
    }

    if (studentCountDelta > 0) {
      batch.update(adminDb.collection('schools').doc(schoolId), {
        studentCount: FieldValue.increment(studentCountDelta),
      });
    }

    try {
      await batch.commit();
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Batch write failed';
      result.errors.push({ row: i + 1, message: `Batch error: ${message}` });
      result.errorCount += chunk.length;
      result.successCount -= chunk.length;
    }
  }

  return result;
}
