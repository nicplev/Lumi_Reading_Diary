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
    characterId: data.characterId,
    isActive: data.isActive ?? true,
    status: data.status === 'archived' ? 'archived' : undefined,
    archivedAt: data.archivedAt?.toDate(),
    archivedReason: data.archivedReason,
    archivedBy: data.archivedBy,
    createdAt: data.createdAt?.toDate() ?? new Date(),
    enrolledAt: data.enrolledAt?.toDate(),
    additionalInfo: data.additionalInfo,
    // Legacy 'pending' rows (and unset rows) are surfaced as 'not_enrolled' —
    // we collapsed the two when the four-state model was simplified.
    enrollmentStatus: data.enrollmentStatus === 'pending' ? 'not_enrolled' : data.enrollmentStatus,
    parentEmail: data.parentEmail ?? data.additionalInfo?.pendingParentEmail,
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
    // Denormalized guardian projections (name + relationship label only),
    // maintained server-side by the syncGuardianProfiles Cloud Function.
    guardianProfiles: data.guardianProfiles ?? {},
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
    parentEmail?: string;
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
      enrollmentStatus: 'not_enrolled',
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
  data: Partial<Pick<Student, 'firstName' | 'lastName' | 'studentId' | 'classId' | 'currentReadingLevel' | 'parentEmail'>>
): Promise<void> {
  const studentRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId);

  // When the edit changes a student's class, keep the class rosters
  // (`class.studentIds`) in sync — same as moveStudentToClass. A bare
  // `.update({ classId })` would leave the student in the OLD class's array and
  // never add them to the new one, orphaning the id. That drift is exactly what
  // makes analytics undercount "X of N students active" (the array-derived
  // denominator silently loses reassigned students). The per-student `classId`
  // stays the source of truth; the arrays are denormalised mirrors.
  if (data.classId !== undefined) {
    const snap = await studentRef.get();
    const fromClassId = (snap.data()?.classId ?? '') as string;
    const toClassId = data.classId ?? '';
    if (fromClassId !== toClassId) {
      const classesRef = adminDb.collection('schools').doc(schoolId).collection('classes');
      const batch = adminDb.batch();
      batch.update(studentRef, data);
      if (fromClassId) {
        batch.update(classesRef.doc(fromClassId), { studentIds: FieldValue.arrayRemove(studentId) });
      }
      if (toClassId) {
        batch.update(classesRef.doc(toClassId), { studentIds: FieldValue.arrayUnion(studentId) });
      }
      await batch.commit();
      return;
    }
  }

  await studentRef.update(data);
}

export async function deleteStudent(schoolId: string, studentId: string): Promise<void> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentDoc = await schoolRef.collection('students').doc(studentId).get();

  if (!studentDoc.exists) throw new Error('Student not found');
  const data = studentDoc.data()!;
  const classId = data.classId as string | undefined;
  const parentIds = (data.parentIds ?? []) as string[];

  // Decide parent-side action (delete orphan vs arrayRemove) by re-reading each parent.
  const parentsRef = schoolRef.collection('parents');
  const parentActions: Array<{ ref: FirebaseFirestore.DocumentReference; action: 'delete' | 'remove' }> = [];
  if (parentIds.length > 0) {
    const parentSnaps = await Promise.all(parentIds.map((pid) => parentsRef.doc(pid).get()));
    for (const snap of parentSnaps) {
      if (!snap.exists) continue;
      const linked = (snap.data()!.linkedChildren ?? []) as string[];
      const remaining = linked.filter((id) => id !== studentId);
      parentActions.push({ ref: snap.ref, action: remaining.length === 0 ? 'delete' : 'remove' });
    }
  }

  // Revoke any active link codes pointing at this student so the next
  // parent who tries to redeem one isn't stranded at "student-missing"
  // inside linkParentToStudent. Mirrors the cascade in the Cloud Function
  // deleteStudentWithCascade.
  const activeCodes = await adminDb
    .collection('studentLinkCodes')
    .where('studentId', '==', studentId)
    .where('status', '==', 'active')
    .get();

  const batch = adminDb.batch();
  batch.delete(studentDoc.ref);

  for (const codeDoc of activeCodes.docs) {
    batch.update(codeDoc.ref, {
      status: 'revoked',
      revokedAt: FieldValue.serverTimestamp(),
      revokeReason: 'student_deleted',
    });
  }

  if (classId) {
    batch.update(schoolRef.collection('classes').doc(classId), {
      studentIds: FieldValue.arrayRemove(studentId),
    });
  }

  for (const { ref, action } of parentActions) {
    if (action === 'delete') {
      batch.delete(ref);
    } else {
      batch.update(ref, { linkedChildren: FieldValue.arrayRemove(studentId) });
    }
  }

  // Archived students already left the count when they were archived —
  // decrementing again on delete-forever would double-count.
  if ((data.isActive ?? true) === true) {
    batch.update(schoolRef, {
      studentCount: FieldValue.increment(-1),
    });
  }

  await batch.commit();
}

export async function deleteStudents(schoolId: string, studentIds: string[]): Promise<number> {
  if (studentIds.length === 0) return 0;

  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');
  const parentsRef = schoolRef.collection('parents');

  const snapshots = await Promise.all(studentIds.map((id) => studentsRef.doc(id).get()));
  const existing = snapshots.filter((s) => s.exists);
  if (existing.length === 0) return 0;

  const deletedIdSet = new Set(existing.map((s) => s.id));

  const classMembersRemoved = new Map<string, string[]>();
  const parentChildrenRemoved = new Map<string, string[]>();
  for (const snap of existing) {
    const data = snap.data()!;
    const classId = data.classId as string | undefined;
    if (classId) {
      const list = classMembersRemoved.get(classId) ?? [];
      list.push(snap.id);
      classMembersRemoved.set(classId, list);
    }
    const pIds = (data.parentIds ?? []) as string[];
    for (const pid of pIds) {
      const list = parentChildrenRemoved.get(pid) ?? [];
      if (!list.includes(snap.id)) list.push(snap.id);
      parentChildrenRemoved.set(pid, list);
    }
  }

  // Re-read each affected parent to decide delete vs arrayRemove.
  const parentActions: Array<{ ref: FirebaseFirestore.DocumentReference; action: 'delete' | 'remove'; ids: string[] }> = [];
  if (parentChildrenRemoved.size > 0) {
    const parentSnaps = await Promise.all(
      Array.from(parentChildrenRemoved.keys()).map((pid) => parentsRef.doc(pid).get())
    );
    for (const snap of parentSnaps) {
      if (!snap.exists) continue;
      const linked = (snap.data()!.linkedChildren ?? []) as string[];
      const idsToRemove = parentChildrenRemoved.get(snap.id) ?? [];
      const remaining = linked.filter((id) => !deletedIdSet.has(id));
      parentActions.push({
        ref: snap.ref,
        action: remaining.length === 0 ? 'delete' : 'remove',
        ids: idsToRemove,
      });
    }
  }

  // Collect all active link codes pointing at the deleted students so we
  // can revoke them in the same operation. Firestore caps `in` queries at
  // 30 values; chunk to stay under that.
  const deletedIds = Array.from(deletedIdSet);
  const activeCodeRefs: FirebaseFirestore.DocumentReference[] = [];
  const CODE_QUERY_CHUNK = 30;
  for (let i = 0; i < deletedIds.length; i += CODE_QUERY_CHUNK) {
    const chunk = deletedIds.slice(i, i + CODE_QUERY_CHUNK);
    const snap = await adminDb
      .collection('studentLinkCodes')
      .where('studentId', 'in', chunk)
      .where('status', '==', 'active')
      .get();
    for (const doc of snap.docs) activeCodeRefs.push(doc.ref);
  }

  const BATCH_SIZE = 400;
  for (let i = 0; i < existing.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const snap of existing.slice(i, i + BATCH_SIZE)) {
      batch.delete(snap.ref);
    }
    await batch.commit();
  }

  // Revoke link codes in their own batched commits so we don't blow past
  // the 500-write batch ceiling when wiping a large class.
  for (let i = 0; i < activeCodeRefs.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const ref of activeCodeRefs.slice(i, i + BATCH_SIZE)) {
      batch.update(ref, {
        status: 'revoked',
        revokedAt: FieldValue.serverTimestamp(),
        revokeReason: 'student_deleted',
      });
    }
    await batch.commit();
  }

  const metaBatch = adminDb.batch();
  for (const [classId, ids] of classMembersRemoved) {
    metaBatch.update(classesRef.doc(classId), {
      studentIds: FieldValue.arrayRemove(...ids),
    });
  }
  for (const { ref, action, ids } of parentActions) {
    if (action === 'delete') {
      metaBatch.delete(ref);
    } else {
      metaBatch.update(ref, { linkedChildren: FieldValue.arrayRemove(...ids) });
    }
  }
  // Only active students still count toward studentCount — archived ones left
  // the count at archive time (double-decrement guard).
  const activeDeleted = existing.filter((s) => (s.data()!.isActive ?? true) === true).length;
  if (activeDeleted > 0) {
    metaBatch.update(schoolRef, {
      studentCount: FieldValue.increment(-activeDeleted),
    });
  }
  await metaBatch.commit();

  return existing.length;
}

/**
 * Soft-archive students: hide them from every roster/report surface while
 * preserving the doc (reading history, stats, parent links) for restore.
 *
 * What it does per student: `isActive: false` + archive marker fields, removes
 * the id from the class roster mirror (`class.studentIds` — analytics and
 * `reconcileClassStats` derive from it), revokes any active link codes, and
 * decrements `school.studentCount` (displayed as current enrolment; archived
 * students shouldn't count toward per-student pricing).
 *
 * Deliberately does NOT touch: `classId` (kept as the restore target and for
 * history), `parentIds`/parent docs (unlinking cascades into parent-account
 * deletion — irreversibly destructive for a reversible state; the parent app
 * simply shows the child in the expired-access state), `access`, or stats.
 */
export async function archiveStudents(
  schoolId: string,
  studentIds: string[],
  reason: 'graduated' | 'left' | 'manual',
  archivedBy: string
): Promise<number> {
  if (studentIds.length === 0) return 0;

  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');

  const snapshots = await Promise.all(studentIds.map((id) => studentsRef.doc(id).get()));
  // Only archive currently-active students — re-archiving is a no-op so the
  // count (and studentCount decrement) stays honest on retries.
  const targets = snapshots.filter((s) => s.exists && (s.data()!.isActive ?? true) === true);
  if (targets.length === 0) return 0;

  const classMembersRemoved = new Map<string, string[]>();
  for (const snap of targets) {
    const classId = snap.data()!.classId as string | undefined;
    if (classId) {
      const list = classMembersRemoved.get(classId) ?? [];
      list.push(snap.id);
      classMembersRemoved.set(classId, list);
    }
  }

  // Revoke active link codes so a parent can't redeem a code for a student who
  // has left. Firestore caps `in` queries at 30 values; chunk to stay under.
  const targetIds = targets.map((s) => s.id);
  const activeCodeRefs: FirebaseFirestore.DocumentReference[] = [];
  const CODE_QUERY_CHUNK = 30;
  for (let i = 0; i < targetIds.length; i += CODE_QUERY_CHUNK) {
    const chunk = targetIds.slice(i, i + CODE_QUERY_CHUNK);
    const snap = await adminDb
      .collection('studentLinkCodes')
      .where('studentId', 'in', chunk)
      .where('status', '==', 'active')
      .get();
    for (const doc of snap.docs) activeCodeRefs.push(doc.ref);
  }

  const now = new Date();
  const BATCH_SIZE = 400;
  for (let i = 0; i < targets.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const snap of targets.slice(i, i + BATCH_SIZE)) {
      batch.update(snap.ref, {
        isActive: false,
        status: 'archived',
        archivedAt: now,
        archivedReason: reason,
        archivedBy,
      });
    }
    await batch.commit();
  }

  for (let i = 0; i < activeCodeRefs.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const ref of activeCodeRefs.slice(i, i + BATCH_SIZE)) {
      batch.update(ref, {
        status: 'revoked',
        revokedAt: FieldValue.serverTimestamp(),
        revokeReason: 'student_archived',
      });
    }
    await batch.commit();
  }

  const metaBatch = adminDb.batch();
  for (const [classId, ids] of classMembersRemoved) {
    metaBatch.update(classesRef.doc(classId), {
      studentIds: FieldValue.arrayRemove(...ids),
    });
  }
  metaBatch.update(schoolRef, {
    studentCount: FieldValue.increment(-targets.length),
  });
  await metaBatch.commit();

  return targets.length;
}

export interface RestoreResult {
  count: number;
  /** Students that could not be restored, with the reason (shown in the UI). */
  skipped: { id: string; name: string; reason: string }[];
}

/**
 * Reverse of archiveStudents. Restores into the student's previous class when
 * that class is still active; otherwise restores as unassigned (`classId: ''`)
 * so the admin re-homes them from the Students page. Blocked per-student when
 * an ACTIVE student now holds the same external `studentId` — two live students
 * must never share the upsert key the CSV imports match on.
 *
 * Does not resurrect revoked link codes — staff issue a fresh code if the
 * family needs to re-link (they usually never unlinked, so most restores need
 * nothing).
 */
export async function restoreStudents(schoolId: string, studentIds: string[]): Promise<RestoreResult> {
  const result: RestoreResult = { count: 0, skipped: [] };
  if (studentIds.length === 0) return result;

  const schoolRef = adminDb.collection('schools').doc(schoolId);
  const studentsRef = schoolRef.collection('students');
  const classesRef = schoolRef.collection('classes');

  const snapshots = await Promise.all(studentIds.map((id) => studentsRef.doc(id).get()));
  const archived = snapshots.filter((s) => s.exists && (s.data()!.isActive ?? true) === false);
  if (archived.length === 0) return result;

  // External-ID conflict check: an active student holding the same studentId
  // would break CSV upsert matching (and createStudent's uniqueness guarantee).
  const externalIds = archived
    .map((s) => (s.data()!.studentId as string | undefined)?.trim())
    .filter((sid): sid is string => !!sid);
  const activeIdHolders = new Set<string>();
  const ID_QUERY_CHUNK = 30;
  for (let i = 0; i < externalIds.length; i += ID_QUERY_CHUNK) {
    const chunk = externalIds.slice(i, i + ID_QUERY_CHUNK);
    const snap = await studentsRef
      .where('studentId', 'in', chunk)
      .where('isActive', '==', true)
      .get();
    for (const doc of snap.docs) {
      const sid = (doc.data().studentId as string | undefined)?.trim();
      if (sid) activeIdHolders.add(sid);
    }
  }

  // Restore into the old class only if it still exists and is active.
  const classIds = Array.from(
    new Set(
      archived
        .map((s) => s.data()!.classId as string | undefined)
        .filter((cid): cid is string => !!cid)
    )
  );
  const classSnaps = await Promise.all(classIds.map((cid) => classesRef.doc(cid).get()));
  const activeClassIds = new Set(
    classSnaps.filter((c) => c.exists && (c.data()!.isActive ?? true) === true).map((c) => c.id)
  );

  const classMembersAdded = new Map<string, string[]>();
  const BATCH_SIZE = 400;
  for (let i = 0; i < archived.length; i += BATCH_SIZE) {
    const batch = adminDb.batch();
    for (const snap of archived.slice(i, i + BATCH_SIZE)) {
      const data = snap.data()!;
      const sid = (data.studentId as string | undefined)?.trim();
      if (sid && activeIdHolders.has(sid)) {
        result.skipped.push({
          id: snap.id,
          name: `${data.firstName ?? ''} ${data.lastName ?? ''}`.trim(),
          reason: `An active student already has Student ID "${sid}"`,
        });
        continue;
      }

      const classId = data.classId as string | undefined;
      const classStillActive = !!classId && activeClassIds.has(classId);
      batch.update(snap.ref, {
        isActive: true,
        status: FieldValue.delete(),
        archivedAt: FieldValue.delete(),
        archivedReason: FieldValue.delete(),
        archivedBy: FieldValue.delete(),
        ...(classStillActive ? {} : { classId: '' }),
      });
      if (classStillActive) {
        const list = classMembersAdded.get(classId) ?? [];
        list.push(snap.id);
        classMembersAdded.set(classId, list);
      }
      result.count++;
    }
    await batch.commit();
  }

  if (result.count > 0) {
    const metaBatch = adminDb.batch();
    for (const [classId, ids] of classMembersAdded) {
      metaBatch.update(classesRef.doc(classId), {
        studentIds: FieldValue.arrayUnion(...ids),
      });
    }
    metaBatch.update(schoolRef, {
      studentCount: FieldValue.increment(result.count),
    });
    await metaBatch.commit();
  }

  return result;
}

export async function moveStudentToClass(
  schoolId: string,
  studentId: string,
  fromClassId: string | null,
  toClassId: string | null,
): Promise<void> {
  const batch = adminDb.batch();

  const studentRef = adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(studentId);

  batch.update(studentRef, { classId: toClassId ?? '' });

  if (fromClassId) {
    batch.update(
      adminDb.collection('schools').doc(schoolId).collection('classes').doc(fromClassId),
      { studentIds: FieldValue.arrayRemove(studentId) }
    );
  }

  if (toClassId) {
    batch.update(
      adminDb.collection('schools').doc(schoolId).collection('classes').doc(toClassId),
      { studentIds: FieldValue.arrayUnion(studentId) }
    );
  }

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

/**
 * Parse a date-of-birth cell from a CSV import into a valid Date, or null.
 * Handles ISO `yyyy-mm-dd`, Australian `dd/mm/yyyy` (and `dd-mm-yyyy`, 2-digit
 * years), and Excel serial numbers. Crucially it NEVER returns an Invalid Date:
 * `new Date("22/05/2020")` yields Invalid Date, and writing that to Firestore
 * throws "Value for argument \"seconds\" is not a valid integer", which used to
 * fail the entire 400-row batch. Unrecognised cells return null so the student
 * still imports (without a DOB) instead of nuking the import.
 */
export function parseImportDate(raw: string | undefined | null): Date | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (s === '') return null;

  // Excel serial (days since the 1899-12-30 epoch). Bare integer, plausible range.
  if (/^\d{1,6}$/.test(s)) {
    const serial = parseInt(s, 10);
    if (serial > 0 && serial < 200000) {
      const d = new Date(Date.UTC(1899, 11, 30) + serial * 86400000);
      return isNaN(d.getTime()) ? null : d;
    }
    return null;
  }

  // Australian dd/mm/yyyy (or dd-mm-yyyy / dd.mm.yyyy, 2- or 4-digit year).
  const au = s.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})$/);
  if (au) {
    const day = parseInt(au[1], 10);
    const month = parseInt(au[2], 10);
    let year = parseInt(au[3], 10);
    if (year < 100) year += year < 50 ? 2000 : 1900;
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      const d = new Date(Date.UTC(year, month - 1, day));
      // Reject overflow (e.g. 31/02 rolling into March).
      if (d.getUTCMonth() === month - 1 && d.getUTCDate() === day) return d;
    }
    return null;
  }

  // ISO yyyy-mm-dd.
  if (/^\d{4}-\d{1,2}-\d{1,2}/.test(s)) {
    const d = new Date(s);
    return isNaN(d.getTime()) ? null : d;
  }

  // Anything else is ambiguous/locale-dependent — refuse rather than guess.
  return null;
}

export async function importStudents(
  schoolId: string,
  rows: CSVRow[],
  createdBy: string
): Promise<ImportResult> {
  const result: ImportResult = { successCount: 0, errorCount: 0, errors: [], createdClassNames: [] };
  const createdClassSet = new Set<string>();

  // Pre-fetch existing classes (name → id) and existing students keyed by their
  // external studentId (for upsert — re-importing the same file must not create
  // duplicates).
  const [classesSnap, studentsSnap] = await Promise.all([
    adminDb.collection('schools').doc(schoolId).collection('classes').where('isActive', '==', true).get(),
    adminDb.collection('schools').doc(schoolId).collection('students').get(),
  ]);

  const classMap = new Map<string, string>(); // lowercased name → id
  classesSnap.docs.forEach((doc) => {
    const name = doc.data().name;
    if (typeof name === 'string') classMap.set(name.toLowerCase(), doc.id);
  });

  const studentIdMap = new Map<string, string>(); // external studentId → doc id
  studentsSnap.docs.forEach((doc) => {
    const sid = doc.data().studentId;
    if (typeof sid === 'string' && sid.trim() !== '') studentIdMap.set(sid.trim(), doc.id);
  });

  const BATCH_SIZE = 400;
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const chunk = rows.slice(i, i + BATCH_SIZE);
    const batch = adminDb.batch();
    let studentCountDelta = 0; // NEW students only (upserts don't change the count)
    let committedInChunk = 0;
    const classesCreatedThisChunk: Array<{ name: string; key: string }> = [];

    for (let j = 0; j < chunk.length; j++) {
      const row = chunk[j];
      const rowIndex = i + j + 1;

      if (!row.firstName || !row.lastName || !row.className) {
        result.errors.push({ row: rowIndex, message: 'Missing required fields (firstName, lastName, className)' });
        result.errorCount++;
        continue;
      }

      // Validate the date-of-birth PER ROW, before it can reach the batch —
      // a bad cell nulls the DOB (with a per-row note) instead of throwing.
      let dob: Date | null = null;
      if (row.dateOfBirth && row.dateOfBirth.trim() !== '') {
        dob = parseImportDate(row.dateOfBirth);
        if (dob === null) {
          result.errors.push({
            row: rowIndex,
            message: `Unrecognised date of birth "${row.dateOfBirth}" — imported without it (use dd/mm/yyyy or yyyy-mm-dd)`,
          });
        }
      }

      // Find or create the class.
      const classKey = row.className.toLowerCase();
      let classId = classMap.get(classKey);
      if (!classId) {
        const classRef = adminDb.collection('schools').doc(schoolId).collection('classes').doc();
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
        classMap.set(classKey, classId);
        classesCreatedThisChunk.push({ name: row.className, key: classKey });
      }

      const externalId = row.studentId?.trim() || '';
      const existingDocId = externalId ? studentIdMap.get(externalId) : undefined;

      if (existingDocId) {
        // Upsert: merge only the CSV-editable fields so re-import updates the
        // student in place without resetting stats / parentIds / enrollment.
        const studentRef = adminDb.collection('schools').doc(schoolId).collection('students').doc(existingDocId);
        batch.set(
          studentRef,
          {
            firstName: row.firstName,
            lastName: row.lastName,
            classId,
            dateOfBirth: dob,
            currentReadingLevel: row.readingLevel || null,
            parentEmail: row.parentEmail || null,
            updatedAt: new Date(),
          },
          { merge: true }
        );
        batch.update(
          adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId),
          { studentIds: FieldValue.arrayUnion(existingDocId) }
        );
      } else {
        const studentRef = adminDb.collection('schools').doc(schoolId).collection('students').doc();
        batch.set(studentRef, {
          studentId: externalId || null,
          firstName: row.firstName,
          lastName: row.lastName,
          classId,
          schoolId,
          dateOfBirth: dob,
          currentReadingLevel: row.readingLevel || null,
          parentEmail: row.parentEmail || null,
          enrollmentStatus: 'not_enrolled',
          parentIds: [],
          isActive: true,
          createdAt: new Date(),
          enrolledAt: new Date(),
          createdBy,
          additionalInfo: row.parentEmail ? { pendingParentEmail: row.parentEmail } : {},
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
        batch.update(
          adminDb.collection('schools').doc(schoolId).collection('classes').doc(classId),
          { studentIds: FieldValue.arrayUnion(studentRef.id) }
        );
        if (externalId) studentIdMap.set(externalId, studentRef.id);
        studentCountDelta++;
      }

      committedInChunk++;
    }

    if (studentCountDelta > 0) {
      batch.update(adminDb.collection('schools').doc(schoolId), {
        studentCount: FieldValue.increment(studentCountDelta),
      });
    }

    try {
      await batch.commit();
      // Only now that the write landed do we count successes and report the
      // classes that were actually created (no phantom classes on failure).
      result.successCount += committedInChunk;
      for (const c of classesCreatedThisChunk) {
        if (!createdClassSet.has(c.key)) {
          createdClassSet.add(c.key);
          result.createdClassNames.push(c.name);
        }
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Batch write failed';
      result.errors.push({ row: i + 1, message: `Batch error: ${message}` });
      result.errorCount += committedInChunk;
      // Roll back the in-memory class additions so a later chunk / retry can
      // recreate them (they weren't actually written).
      for (const c of classesCreatedThisChunk) classMap.delete(c.key);
    }
  }

  return result;
}
