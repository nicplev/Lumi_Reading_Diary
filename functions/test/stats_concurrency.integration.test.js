/**
 * Regression test for the stats lost-update race.
 *
 * applyStudentStatsDelta / applyClassStatsDelta accumulate: read the current
 * totals, add a delta, write back. When that read-modify-write is not
 * transactional and several logs for the same student land at once — a
 * batched import, or an offline parent whose queued logs all flush on
 * reconnect — every invocation reads the same stale totals and the increments
 * are lost. Seeding one class this way undercounted 5 of 9 students.
 *
 * These tests fire the delta handlers concurrently and assert the totals equal
 * the sum of every log. They fail on the non-transactional implementation.
 *
 * Run: npm run test:stats:concurrency
 */

const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const PROJECT_ID = 'demo-lumi-stats-concurrency';
let db;
let applyStudentStatsDelta;
let applyClassStatsDelta;

before(() => {
  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
  ({
    applyStudentStatsDelta,
    applyClassStatsDelta,
  } = require('../lib/stats_aggregation.js'));
});

/**
 * Creates a log and returns the {before, after} Change the trigger would see.
 * `before` is captured pre-write so it is a genuine not-exists snapshot
 * carrying the right doc id.
 */
async function createLogChange(logsRef, id, data) {
  const ref = logsRef.doc(id);
  const beforeSnap = await ref.get();
  await ref.set(data);
  const afterSnap = await ref.get();
  return {before: beforeSnap, after: afterSnap};
}

function logDoc(studentId, classId, isoDate, minutes) {
  return {
    studentId,
    classId,
    schoolId: 'school_conc',
    date: admin.firestore.Timestamp.fromDate(new Date(isoDate)),
    minutesRead: minutes,
    status: 'completed',
    bookTitles: ['Matilda'],
  };
}

test('concurrent student-stat deltas do not lose increments', async () => {
  const school = db.doc('schools/school_conc');
  await school.set({timezone: 'Australia/Melbourne'});
  const logs = school.collection('readingLogs');

  const studentRef = school.collection('students').doc('student_conc');
  await studentRef.set({
    classId: 'class_conc',
    // readingDates present => incremental path (not the self-heal recompute)
    stats: {totalMinutesRead: 0, totalBooksRead: 0, readingDates: []},
  });

  // Eight sessions on eight distinct days, mirroring a week of seeded data.
  const minutes = [21, 18, 25, 30, 12, 27, 16, 22];
  const changes = [];
  for (let i = 0; i < minutes.length; i++) {
    const day = String(13 + i).padStart(2, '0');
    changes.push(await createLogChange(
      logs, `sc_log_${i}`,
      logDoc('student_conc', 'class_conc', `2026-07-${day}T08:00:00.000Z`, minutes[i]),
    ));
  }

  // Fire every trigger at once — this is the condition that loses updates.
  await Promise.all(
    changes.map((c) => applyStudentStatsDelta(c, 'school_conc')),
  );

  const expectedMinutes = minutes.reduce((a, b) => a + b, 0);
  const stats = (await studentRef.get()).data().stats;
  assert.equal(stats.totalMinutesRead, expectedMinutes,
    `expected ${expectedMinutes} minutes, got ${stats.totalMinutesRead}`);
  assert.equal(stats.totalBooksRead, minutes.length);
  assert.equal(stats.totalReadingDays, minutes.length);
  assert.equal(stats.readingDates.length, minutes.length);
});

test('concurrent class-stat deltas do not lose increments', async () => {
  const school = db.doc('schools/school_conc2');
  await school.set({timezone: 'Australia/Melbourne'});
  const logs = school.collection('readingLogs');

  const classRef = school.collection('classes').doc('class_conc2');
  await classRef.set({
    name: '3A',
    stats: {totalMinutesRead: 0, totalBooksRead: 0, activeStudents: 0, activeStudentIds: []},
  });

  // Several students in the same class all writing at once — the class doc is
  // the hotter document, since every student in the class contends on it.
  const students = ['s1', 's2', 's3', 's4'];
  for (const s of students) {
    await school.collection('students').doc(s).set({classId: 'class_conc2'});
  }

  const minutes = 20;
  const changes = [];
  for (const s of students) {
    for (let i = 0; i < 3; i++) {
      const day = String(13 + i).padStart(2, '0');
      changes.push(await createLogChange(
        logs, `cc_${s}_${i}`,
        logDoc(s, 'class_conc2', `2026-07-${day}T08:00:00.000Z`, minutes),
      ));
    }
  }

  await Promise.all(changes.map((c) => applyClassStatsDelta(c, 'school_conc2')));

  const expected = changes.length * minutes;
  const stats = (await classRef.get()).data().stats;
  assert.equal(stats.totalMinutesRead, expected,
    `expected ${expected} minutes, got ${stats.totalMinutesRead}`);
  assert.equal(stats.totalBooksRead, changes.length);
  assert.equal(stats.activeStudents, students.length);
});

after(async () => {
  await admin.app().delete();
});
