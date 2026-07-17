const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const PROJECT_ID = 'demo-lumi-daily-summary';
let db;
let syncReadingLogDailySummary;
let reconcileClassDailyReadingPass;

before(() => {
  admin.initializeApp({projectId: PROJECT_ID});
  db = admin.firestore();
  ({
    syncReadingLogDailySummary,
    reconcileClassDailyReadingPass,
  } = require('../lib/class_daily_reading.js'));
});

test('reconciliation repairs corrupted summaries from projection state', async () => {
  const school = db.doc('schools/school_2');
  const logs = school.collection('readingLogs');
  await school.set({timezone: 'Australia/Melbourne'});
  await logs.doc('log_a').set({
    classId: 'class_2',
    studentId: 'student_a',
    date: admin.firestore.Timestamp.fromDate(
      new Date('2026-07-17T08:00:00.000Z'),
    ),
    minutesRead: 25,
    status: 'completed',
  });
  await syncReadingLogDailySummary('school_2', 'log_a');
  const before = await school.collection('classDailyReading').get();
  assert.equal(before.size, 1);
  await before.docs[0].ref.update({totalMinutes: 9999, logCount: 99});
  await school.collection('classDailyReading').doc('stale').set({
    classId: 'class_2', localDate: '2020-01-01', logCount: 1,
  });

  const result = await reconcileClassDailyReadingPass(['school_2']);
  const repaired = await school.collection('classDailyReading').get();
  assert.equal(result.schools, 1);
  assert.equal(result.logs, 1);
  assert.equal(repaired.size, 1);
  assert.equal(repaired.docs[0].data().totalMinutes, 25);
  assert.equal(repaired.docs[0].data().logCount, 1);
});

after(async () => {
  await admin.app().delete();
});

test('transaction converges across duplicate, update, invalidation and delete', async () => {
  const school = db.doc('schools/school_1');
  const logs = school.collection('readingLogs');
  await school.set({timezone: 'Australia/Melbourne'});
  await logs.doc('log_1').set({
    classId: 'class_1',
    studentId: 'student_1',
    date: admin.firestore.Timestamp.fromDate(
      new Date('2026-07-16T14:30:00.000Z'),
    ),
    minutesRead: 20,
    status: 'completed',
  });

  await syncReadingLogDailySummary('school_1', 'log_1');
  await syncReadingLogDailySummary('school_1', 'log_1');
  let summaries = await school.collection('classDailyReading').get();
  assert.equal(summaries.size, 1);
  assert.equal(summaries.docs[0].data().localDate, '2026-07-17');
  assert.equal(summaries.docs[0].data().logCount, 1);
  assert.equal(summaries.docs[0].data().totalMinutes, 20);

  await logs.doc('log_1').update({minutesRead: 35});
  await syncReadingLogDailySummary('school_1', 'log_1');
  summaries = await school.collection('classDailyReading').get();
  assert.equal(summaries.docs[0].data().logCount, 1);
  assert.equal(summaries.docs[0].data().totalMinutes, 35);

  await logs.doc('log_2').set({
    classId: 'class_1',
    studentId: 'student_1',
    date: admin.firestore.Timestamp.fromDate(
      new Date('2026-07-16T15:00:00.000Z'),
    ),
    minutesRead: 10,
    status: 'partial',
    loggedByRole: 'teacher',
  });
  await syncReadingLogDailySummary('school_1', 'log_2');
  summaries = await school.collection('classDailyReading').get();
  assert.equal(summaries.docs[0].data().logCount, 2);
  assert.equal(summaries.docs[0].data().activeStudentCount, 1);
  assert.equal(summaries.docs[0].data().totalMinutes, 45);
  assert.equal(summaries.docs[0].data().teacherLogCount, 1);

  await logs.doc('log_1').update({validationStatus: 'invalid'});
  await syncReadingLogDailySummary('school_1', 'log_1');
  summaries = await school.collection('classDailyReading').get();
  assert.equal(summaries.docs[0].data().logCount, 1);
  assert.equal(summaries.docs[0].data().totalMinutes, 10);

  await logs.doc('log_2').delete();
  await syncReadingLogDailySummary('school_1', 'log_2');
  summaries = await school.collection('classDailyReading').get();
  assert.equal(summaries.size, 0);
  assert.equal(
    (await school.collection('readingLogSummaryState').get()).size,
    0,
  );
});
