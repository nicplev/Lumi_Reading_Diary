// Integration test for the single-log dependent-data cascade
// (functions/src/reading_log_cleanup.ts). Drives the exported core directly
// against the Firestore + Storage emulators, same harness pattern as
// deletion.integration.test.js.
//
// Run:
//   npm run build && ../scripts/with-jdk21.sh firebase emulators:exec \
//     --config ../firebase.deletion.json --only firestore,storage \
//     --project demo-lumi-log-cleanup \
//     "node --test test/reading_log_cleanup.integration.test.js"
const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const PROJECT_ID = 'demo-lumi-log-cleanup';
const BUCKET = `${PROJECT_ID}.appspot.com`;
const SCHOOL_ID = 'cleanup_school';
const STUDENT_ID = 'cleanup_student';
const LOG_ID = 'cleanup_log_1';
const SLOT_DATE = '2026-07-24';

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
  }
});

after(async () => {
  await Promise.all(admin.apps.map((app) => app.delete()));
});

beforeEach(async () => {
  const db = admin.firestore();
  await db.recursiveDelete(db.collection('schools'));
  await db.recursiveDelete(db.collection('aiEvalJobs'));
});

function logData(overrides = {}) {
  return {
    schoolId: SCHOOL_ID,
    studentId: STUDENT_ID,
    parentId: 'cleanup_parent',
    classId: 'cleanup_class',
    date: admin.firestore.Timestamp.now(),
    occurredOn: SLOT_DATE,
    context: 'home',
    minutesRead: 15,
    targetMinutes: 20,
    status: 'completed',
    bookTitles: ['The Bad Guys'],
    ...overrides,
  };
}

async function seedLogWithDependents({ slotLogId = LOG_ID, student = {} } = {}) {
  const db = admin.firestore();
  const school = db.collection('schools').doc(SCHOOL_ID);
  await school.set({ name: 'Cleanup school', timezone: 'Australia/Sydney' });
  await school.collection('students').doc(STUDENT_ID).set({
    schoolId: SCHOOL_ID,
    classId: 'cleanup_class',
    firstName: 'Lincoln',
    isActive: true,
    ...student,
  });
  const logRef = school.collection('readingLogs').doc(LOG_ID);
  await logRef.set(logData());
  await logRef.collection('comments').doc('c1').set({
    authorId: 't1', authorRole: 'teacher', authorName: 'Ms Lee',
    body: 'Great reading!', createdAt: admin.firestore.Timestamp.now(),
    studentId: STUDENT_ID, parentId: 'cleanup_parent',
  });
  await school.collection('comprehensionEvals').doc(LOG_ID).set({
    transcript: 'the wolf was good actually', level: 3,
  });
  await db.collection('aiEvalJobs').doc(`${SCHOOL_ID}_${LOG_ID}`).set({
    schoolId: SCHOOL_ID, logId: LOG_ID, state: 'done',
  });
  await school.collection('students').doc(STUDENT_ID)
    .collection('quickSlots').doc(SLOT_DATE).set({
      logId: slotLogId, byUid: 'cleanup_parent',
      createdAt: admin.firestore.Timestamp.now(),
    });
  const bucket = admin.storage().bucket();
  await bucket.file(`schools/${SCHOOL_ID}/comprehension_audio/${LOG_ID}.m4a`)
    .save(Buffer.from('audio'), { contentType: 'audio/mp4' });
  await bucket.file(`comprehension_audio_uploads/${SCHOOL_ID}/${LOG_ID}.m4a`)
    .save(Buffer.from('pending'), { contentType: 'audio/mp4' });
  return logRef;
}

test('cascade removes comments, audio, AI eval artifacts and the held quick slot', async () => {
  const { cleanupDeletedReadingLog } = require('../lib/reading_log_cleanup');
  const db = admin.firestore();
  const logRef = await seedLogWithDependents();
  const data = (await logRef.get()).data();
  await logRef.delete();

  const counts = await cleanupDeletedReadingLog(SCHOOL_ID, LOG_ID, data);

  assert.equal(counts.quickSlotsFreed, 1);
  assert.equal(counts.commentThreadsCleared, 1);
  assert.equal(counts.aiEvalsDeleted, 1);
  assert.equal(counts.aiEvalJobsDeleted, 1);
  assert.equal(counts.storageObjectsDeleted, 2);

  const school = db.collection('schools').doc(SCHOOL_ID);
  assert.equal(
    (await school.collection('readingLogs').doc(LOG_ID)
      .collection('comments').get()).size, 0);
  assert.equal(
    (await school.collection('comprehensionEvals').doc(LOG_ID).get()).exists,
    false);
  assert.equal(
    (await db.collection('aiEvalJobs').doc(`${SCHOOL_ID}_${LOG_ID}`).get())
      .exists, false);
  assert.equal(
    (await school.collection('students').doc(STUDENT_ID)
      .collection('quickSlots').doc(SLOT_DATE).get()).exists, false);
  const [audioExists] = await admin.storage().bucket()
    .file(`schools/${SCHOOL_ID}/comprehension_audio/${LOG_ID}.m4a`).exists();
  const [pendingExists] = await admin.storage().bucket()
    .file(`comprehension_audio_uploads/${SCHOOL_ID}/${LOG_ID}.m4a`).exists();
  assert.equal(audioExists, false);
  assert.equal(pendingExists, false);
});

test('a slot held by a DIFFERENT same-day log is left untouched', async () => {
  const { cleanupDeletedReadingLog } = require('../lib/reading_log_cleanup');
  const db = admin.firestore();
  const logRef = await seedLogWithDependents({ slotLogId: 'some_other_log' });
  const data = (await logRef.get()).data();
  await logRef.delete();

  const counts = await cleanupDeletedReadingLog(SCHOOL_ID, LOG_ID, data);

  assert.equal(counts.quickSlotsFreed ?? 0, 0);
  const slot = await db.collection('schools').doc(SCHOOL_ID)
    .collection('students').doc(STUDENT_ID)
    .collection('quickSlots').doc(SLOT_DATE).get();
  assert.equal(slot.exists, true);
  assert.equal(slot.data().logId, 'some_other_log');
});

test('cascade is idempotent — a retried event is a clean no-op', async () => {
  const { cleanupDeletedReadingLog } = require('../lib/reading_log_cleanup');
  const logRef = await seedLogWithDependents();
  const data = (await logRef.get()).data();
  await logRef.delete();

  await cleanupDeletedReadingLog(SCHOOL_ID, LOG_ID, data);
  const second = await cleanupDeletedReadingLog(SCHOOL_ID, LOG_ID, data);

  assert.equal(second.quickSlotsFreed ?? 0, 0);
  assert.equal(second.aiEvalsDeleted ?? 0, 0);
  assert.equal(second.aiEvalJobsDeleted ?? 0, 0);
  // Storage deletes use ignoreNotFound; comments recursiveDelete of an empty
  // collection is a no-op. Nothing throws on the retry.
});

test('skips when the student cascade is already handling the log', async () => {
  const { cleanupDeletedReadingLog } = require('../lib/reading_log_cleanup');
  const db = admin.firestore();
  const logRef = await seedLogWithDependents({
    student: { pendingDeletion: true },
  });
  const data = (await logRef.get()).data();
  await logRef.delete();

  const counts = await cleanupDeletedReadingLog(SCHOOL_ID, LOG_ID, data);

  assert.equal(counts.skippedStudentCascade, 1);
  // Dependents are left for deletion.ts's own cascade.
  const evalDoc = await db.collection('schools').doc(SCHOOL_ID)
    .collection('comprehensionEvals').doc(LOG_ID).get();
  assert.equal(evalDoc.exists, true);
});
