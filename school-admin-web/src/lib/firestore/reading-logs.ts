import { adminDb } from '@/lib/firebase/admin';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

// Shapes mirror the Flutter ReadingLog / LogComment models so the portal and app
// interoperate. Admin-SDK Timestamps expose .toDate() directly (don't use the
// client-SDK converters here).

export interface ReadingLogRecord {
  id: string;
  studentId: string;
  classId: string;
  date: Date;
  minutesRead: number;
  targetMinutes: number | null;
  status: string;
  bookTitles: string[];
  notes: string | null;
  childFeeling: string | null;
  loggedByRole: string | null;
  loggedByName: string | null;
  loggedByLabel: string | null;
  allocationId: string | null;
  hasComprehensionAudio: boolean;
  comprehensionAudioDurationSec: number | null;
  lastCommentPreview: string | null;
  lastCommentAt: Date | null;
  lastCommentByRole: string | null;
  /** True when a parent has commented and this staff viewer hasn't seen it. */
  hasUnread: boolean;
  createdAt: Date | null;
}

export interface LogCommentRecord {
  id: string;
  authorId: string;
  authorRole: string;
  authorName: string;
  body: string;
  createdAt: Date | null;
}

function logsCol(schoolId: string) {
  return adminDb.collection('schools').doc(schoolId).collection('readingLogs');
}

/**
 * Reading logs for one student, newest first. `hasUnread` is computed for a
 * STAFF viewer — a parent comment they haven't viewed yet — mirroring the app's
 * hasUnreadForTeacher. Uses the existing studentId + date(desc) index.
 */
export async function getReadingLogsForStudent(
  schoolId: string,
  studentId: string,
  viewerUid: string,
  max = 200
): Promise<ReadingLogRecord[]> {
  const snap = await logsCol(schoolId)
    .where('studentId', '==', studentId)
    .orderBy('date', 'desc')
    .limit(max)
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    const lastCommentAt: Date | null = d.lastCommentAt?.toDate() ?? null;
    const viewedAt: Date | null = d.commentsViewedAt?.[viewerUid]?.toDate?.() ?? null;
    const hasUnread =
      !!lastCommentAt &&
      d.lastCommentByRole === 'parent' &&
      (!viewedAt || viewedAt < lastCommentAt);

    return {
      id: doc.id,
      studentId: d.studentId ?? '',
      classId: d.classId ?? '',
      date: d.date?.toDate() ?? d.createdAt?.toDate() ?? new Date(),
      minutesRead: d.minutesRead ?? 0,
      targetMinutes: d.targetMinutes ?? null,
      status: d.status ?? 'completed',
      bookTitles: Array.isArray(d.bookTitles) ? d.bookTitles : [],
      notes: d.notes ?? null,
      childFeeling: d.childFeeling ?? null,
      loggedByRole: d.loggedByRole ?? null,
      loggedByName: d.loggedByName ?? null,
      loggedByLabel: d.loggedByLabel ?? null,
      allocationId: d.allocationId ?? null,
      hasComprehensionAudio: d.comprehensionAudioUploaded === true,
      comprehensionAudioDurationSec: d.comprehensionAudioDurationSec ?? null,
      lastCommentPreview: d.lastCommentPreview ?? null,
      lastCommentAt,
      lastCommentByRole: d.lastCommentByRole ?? null,
      hasUnread,
      createdAt: d.createdAt?.toDate() ?? null,
    };
  });
}

/**
 * Returns the Storage path + duration of a log's comprehension recording, or
 * null if the log has no uploaded audio. The API route streams the bytes from
 * this path (session-gated) — the recording is never exposed via a public URL.
 */
export async function getComprehensionAudio(
  schoolId: string,
  logId: string
): Promise<{ path: string; durationSec: number | null } | null> {
  const snap = await logsCol(schoolId).doc(logId).get();
  if (!snap.exists) return null;
  const d = snap.data()!;
  if (d.comprehensionAudioUploaded !== true || !d.comprehensionAudioPath) return null;
  return {
    path: d.comprehensionAudioPath as string,
    durationSec: typeof d.comprehensionAudioDurationSec === 'number' ? d.comprehensionAudioDurationSec : null,
  };
}

export async function getLogComments(
  schoolId: string,
  logId: string
): Promise<LogCommentRecord[]> {
  const snap = await logsCol(schoolId)
    .doc(logId)
    .collection('comments')
    .orderBy('createdAt', 'asc')
    .get();

  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      authorId: d.authorId ?? '',
      authorRole: d.authorRole ?? 'teacher',
      authorName: d.authorName ?? 'Staff',
      body: d.body ?? '',
      createdAt: d.createdAt?.toDate() ?? null,
    };
  });
}

/**
 * Posts a staff comment and denormalizes the preview onto the log — the same
 * batch the app's addComment performs. The onCommentCreated Cloud Function then
 * mirrors it to `teacherComment` and pushes the parent (skipping proxy logs
 * where parentId === authorId).
 */
export async function addTeacherComment(
  schoolId: string,
  logId: string,
  args: { authorId: string; authorName: string; body: string }
): Promise<{ id: string }> {
  const logRef = logsCol(schoolId).doc(logId);
  const logSnap = await logRef.get();
  if (!logSnap.exists) throw new Error('Reading log not found');
  const log = logSnap.data()!;

  const trimmed = args.body.trim();
  if (!trimmed) throw new Error('Comment cannot be empty');

  const commentRef = logRef.collection('comments').doc();
  const batch = adminDb.batch();
  batch.set(commentRef, {
    authorId: args.authorId,
    authorRole: 'teacher',
    authorName: args.authorName,
    body: trimmed,
    createdAt: FieldValue.serverTimestamp(),
    studentId: log.studentId ?? '',
    parentId: log.parentId ?? '',
  });
  batch.update(logRef, {
    lastCommentPreview: trimmed,
    lastCommentAt: FieldValue.serverTimestamp(),
    lastCommentByRole: 'teacher',
  });
  await batch.commit();
  return { id: commentRef.id };
}

export async function markCommentsRead(
  schoolId: string,
  logId: string,
  viewerUid: string
): Promise<void> {
  await logsCol(schoolId)
    .doc(logId)
    .update({ [`commentsViewedAt.${viewerUid}`]: FieldValue.serverTimestamp() });
}

/**
 * Creates a reading log on behalf of a student (teacher proxy) — mirrors the
 * app's logReadingAsTeacher: parentId = teacher uid, loggedByRole = 'teacher',
 * status = completed. Stats recompute via the aggregateStudentStats /
 * updateClassStats triggers. (validateReadingLog will stamp validationStatus
 * 'invalid' since parentId isn't a guardian — identical to the app today, and
 * harmless: it doesn't block creation or stats.)
 */
export async function createTeacherLog(
  schoolId: string,
  args: {
    studentId: string;
    teacherId: string;
    teacherName: string;
    date: Date;
    minutesRead: number;
    bookTitles: string[];
    notes?: string | null;
    targetMinutes?: number;
  }
): Promise<{ id: string }> {
  const studentSnap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('students')
    .doc(args.studentId)
    .get();
  if (!studentSnap.exists) throw new Error('Student not found');
  const classId = studentSnap.data()?.classId ?? '';

  const logRef = logsCol(schoolId).doc();
  await logRef.set({
    studentId: args.studentId,
    parentId: args.teacherId,
    schoolId,
    classId,
    date: Timestamp.fromDate(args.date),
    minutesRead: args.minutesRead,
    targetMinutes: args.targetMinutes ?? 20,
    status: 'completed',
    bookTitles: args.bookTitles,
    notes: args.notes && args.notes.trim() ? args.notes.trim() : null,
    loggedByRole: 'teacher',
    loggedByName: args.teacherName,
    loggedByLabel: `Logged by ${args.teacherName}`,
    createdAt: FieldValue.serverTimestamp(),
  });
  return { id: logRef.id };
}
