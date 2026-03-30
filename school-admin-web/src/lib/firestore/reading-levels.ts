import { adminDb } from '@/lib/firebase/admin';
import { FieldValue } from 'firebase-admin/firestore';
import type { ReadingLevelEvent } from '@/lib/types';

export interface UpdateLevelInput {
  studentId: string;
  classId: string;
  fromLevel?: string;
  toLevel: string;
  fromLevelIndex?: number;
  toLevelIndex?: number;
  reason?: string;
  source: string;
  changedByUserId: string;
  changedByRole: string;
  changedByName: string;
}

export interface BulkUpdateLevelInput {
  studentIds: string[];
  toLevel: string;
  toLevelIndex?: number;
  reason?: string;
  source: string;
  changedByUserId: string;
  changedByRole: string;
  changedByName: string;
}

export async function updateStudentLevel(
  schoolId: string,
  input: UpdateLevelInput
): Promise<void> {
  const now = new Date();
  const batch = adminDb.batch();

  const studentRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(input.studentId);

  batch.update(studentRef, {
    currentReadingLevel: input.toLevel,
    currentReadingLevelIndex: input.toLevelIndex ?? null,
    readingLevelUpdatedAt: now,
    readingLevelUpdatedBy: input.changedByUserId,
    readingLevelSource: input.source,
    levelHistory: FieldValue.arrayUnion({
      level: input.toLevel,
      changedAt: now,
      changedBy: input.changedByName,
      reason: input.reason ?? null,
    }),
  });

  const eventRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(input.studentId)
    .collection('readingLevelEvents')
    .doc();

  batch.set(eventRef, {
    studentId: input.studentId,
    schoolId,
    classId: input.classId,
    fromLevel: input.fromLevel ?? null,
    toLevel: input.toLevel,
    fromLevelIndex: input.fromLevelIndex ?? null,
    toLevelIndex: input.toLevelIndex ?? null,
    reason: input.reason ?? null,
    source: input.source,
    changedByUserId: input.changedByUserId,
    changedByRole: input.changedByRole,
    changedByName: input.changedByName,
    createdAt: now,
  });

  await batch.commit();
}

export async function getReadingLevelEvents(
  schoolId: string,
  studentId: string
): Promise<ReadingLevelEvent[]> {
  const snap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId)
    .collection('readingLevelEvents')
    .orderBy('createdAt', 'desc')
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      studentId: data.studentId,
      schoolId: data.schoolId,
      classId: data.classId,
      fromLevel: data.fromLevel,
      toLevel: data.toLevel,
      fromLevelIndex: data.fromLevelIndex,
      toLevelIndex: data.toLevelIndex,
      reason: data.reason,
      source: data.source,
      changedByUserId: data.changedByUserId,
      changedByRole: data.changedByRole,
      changedByName: data.changedByName,
      createdAt: data.createdAt?.toDate() ?? new Date(),
    };
  });
}

export async function bulkUpdateLevels(
  schoolId: string,
  input: BulkUpdateLevelInput
): Promise<number> {
  const now = new Date();
  let changed = 0;

  // 2 writes per student (update + event), Firestore limit 500 per batch → 250 students/batch
  const BATCH_SIZE = 250;

  for (let i = 0; i < input.studentIds.length; i += BATCH_SIZE) {
    const chunk = input.studentIds.slice(i, i + BATCH_SIZE);
    const batch = adminDb.batch();

    for (const studentId of chunk) {
      const studentRef = adminDb
        .collection('schools')
        .doc(schoolId)
        .collection('students')
        .doc(studentId);

      batch.update(studentRef, {
        currentReadingLevel: input.toLevel,
        currentReadingLevelIndex: input.toLevelIndex ?? null,
        readingLevelUpdatedAt: now,
        readingLevelUpdatedBy: input.changedByUserId,
        readingLevelSource: input.source,
        levelHistory: FieldValue.arrayUnion({
          level: input.toLevel,
          changedAt: now,
          changedBy: input.changedByName,
          reason: input.reason ?? null,
        }),
      });

      const eventRef = studentRef.collection('readingLevelEvents').doc();
      batch.set(eventRef, {
        studentId,
        schoolId,
        classId: '',
        fromLevel: null,
        toLevel: input.toLevel,
        fromLevelIndex: null,
        toLevelIndex: input.toLevelIndex ?? null,
        reason: input.reason ?? null,
        source: input.source,
        changedByUserId: input.changedByUserId,
        changedByRole: input.changedByRole,
        changedByName: input.changedByName,
        createdAt: now,
      });

      changed++;
    }

    await batch.commit();
  }

  return changed;
}
