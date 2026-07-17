const path = require('node:path');
const fs = require('node:fs');
const crypto = require('node:crypto');
const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const {writeBatch, Timestamp} = require('firebase/firestore');

const PROJECT_ID = 'demo-lumi-scale';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const TEACHER_UID = 'scale_teacher';
const PROFILE_SIZES = [30, 100, 1000];
const DAYS = 7;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => testEnv.cleanup());

async function commitWrites(db, writes) {
  for (let offset = 0; offset < writes.length; offset += 400) {
    const batch = writeBatch(db);
    for (const write of writes.slice(offset, offset + 400)) {
      batch.set(write.ref, write.data);
    }
    await batch.commit();
  }
}

async function seedProfile(studentCount) {
  const schoolId = `scale_school_${studentCount}`;
  const classId = `scale_class_${studentCount}`;
  const now = Date.now();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const school = db.collection('schools').doc(schoolId);
    const writes = [
      {
        ref: school,
        data: {name: 'Synthetic scale school'},
      },
      {
        ref: school.collection('users').doc(TEACHER_UID),
        data: {role: 'teacher', schoolId},
      },
      {
        ref: school.collection('classes').doc(classId),
        data: {
          name: 'Synthetic class',
          teacherId: TEACHER_UID,
          teacherIds: [TEACHER_UID],
          studentIds: Array.from(
            {length: studentCount},
            (_, index) => `student_${index}`,
          ),
        },
      },
    ];

    const dailyShards = new Map();
    for (let student = 0; student < studentCount; student += 1) {
      for (let day = 0; day < DAYS; day += 1) {
        const id = `log_${student}_${day}`;
        writes.push({
          ref: school.collection('readingLogs').doc(id),
          data: {
            schoolId,
            classId,
            studentId: `student_${student}`,
            parentId: `parent_${student}`,
            date: Timestamp.fromMillis(now - day * 24 * 60 * 60 * 1000),
            minutesRead: 15,
            bookTitles: ['Synthetic book'],
            status: 'completed',
          },
        });
        const studentId = `student_${student}`;
        const shard = parseInt(
          crypto.createHash('sha256').update(studentId).digest('hex').slice(0, 8),
          16,
        ) % 8;
        const localDate = new Date(now - day * 24 * 60 * 60 * 1000)
          .toISOString().slice(0, 10);
        const key = `${localDate}_${shard}`;
        const summary = dailyShards.get(key) ?? {
          localDate,
          shard,
          students: {},
          logCount: 0,
          totalMinutes: 0,
        };
        summary.students[studentId] = {logs: 1, minutes: 15, teacherLogs: 0};
        summary.logCount += 1;
        summary.totalMinutes += 15;
        dailyShards.set(key, summary);
      }
    }
    for (const [key, summary] of dailyShards.entries()) {
      writes.push({
        ref: school.collection('classDailyReading').doc(key),
        data: {
          schemaVersion: 1,
          classId,
          localDate: summary.localDate,
          shard: summary.shard,
          logCount: summary.logCount,
          totalMinutes: summary.totalMinutes,
          teacherLogCount: 0,
          activeStudentCount: Object.keys(summary.students).length,
          students: summary.students,
        },
      });
    }
    await commitWrites(db, writes);
  });
  return {schoolId, classId};
}

test('dashboard queries remain authorised at 30/100/1,000 students and expose read growth', async () => {
  const results = [];
  for (const studentCount of PROFILE_SIZES) {
    await testEnv.clearFirestore();
    const {schoolId, classId} = await seedProfile(studentCount);
    const db = testEnv.authenticatedContext(TEACHER_UID).firestore();
    const logs = db.collection('schools').doc(schoolId).collection('readingLogs');
    const weekStart = Timestamp.fromMillis(Date.now() - 8 * 24 * 60 * 60 * 1000);

    const weeklyStarted = performance.now();
    const weekly = await assertSucceeds(
      logs
        .where('classId', '==', classId)
        .where('date', '>=', weekStart)
        .get(),
    );
    const weeklyMs = Math.round(performance.now() - weeklyStarted);

    const recentStarted = performance.now();
    const recent = await assertSucceeds(
      logs
        .where('classId', '==', classId)
        .orderBy('date', 'desc')
        .limit(15)
        .get(),
    );
    const recentMs = Math.round(performance.now() - recentStarted);

    const daily = await assertSucceeds(
      db.collection('schools').doc(schoolId).collection('classDailyReading')
        .where('classId', '==', classId)
        .where('localDate', '>=', '2000-01-01')
        .orderBy('localDate')
        .get(),
    );

    assert.equal(weekly.size, studentCount * DAYS);
    assert.equal(recent.size, 15);
    assert.ok(daily.size <= DAYS * 8);
    results.push({
      students: studentCount,
      seededWeeklyLogs: weekly.size,
      weeklyQueryMs: weeklyMs,
      recentReads: recent.size,
      recentQueryMs: recentMs,
      weeklySummaryReads: daily.size,
      projectedTwelveWeekCalendarReads: studentCount * 84,
      maximumTwelveWeekSummaryReads: 12 * 7 * 8,
    });
  }
  console.log(`SCALE_EVIDENCE ${JSON.stringify(results)}`);
});

test('student history uses a stable bounded cursor when dates are identical', async () => {
  await testEnv.clearFirestore();
  const schoolId = 'history_school';
  const classId = 'history_class';
  const studentId = 'history_student';
  const sharedDate = Timestamp.fromMillis(Date.now());

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const school = db.collection('schools').doc(schoolId);
    const writes = [
      {ref: school, data: {name: 'History cursor school'}},
      {
        ref: school.collection('users').doc(TEACHER_UID),
        data: {role: 'teacher', schoolId},
      },
      {
        ref: school.collection('classes').doc(classId),
        data: {
          name: 'History cursor class',
          teacherId: TEACHER_UID,
          teacherIds: [TEACHER_UID],
          studentIds: [studentId],
        },
      },
    ];
    for (let index = 0; index < 65; index += 1) {
      writes.push({
        ref: school.collection('readingLogs').doc(
          `same_date_${String(index).padStart(3, '0')}`,
        ),
        data: {
          schoolId,
          classId,
          studentId,
          parentId: 'history_parent',
          date: sharedDate,
          minutesRead: 15,
          bookTitles: ['Cursor test'],
          status: 'completed',
        },
      });
    }
    await commitWrites(db, writes);
  });

  const db = testEnv.authenticatedContext(TEACHER_UID).firestore();
  const base = db
    .collection('schools').doc(schoolId).collection('readingLogs')
    .where('studentId', '==', studentId)
    .where('classId', '==', classId)
    .orderBy('date', 'desc');
  const first = await assertSucceeds(base.limit(30).get());
  const second = await assertSucceeds(
    base.startAfter(first.docs.at(-1)).limit(30).get(),
  );
  const third = await assertSucceeds(
    base.startAfter(second.docs.at(-1)).limit(30).get(),
  );
  const ids = [...first.docs, ...second.docs, ...third.docs]
    .map((doc) => doc.id);

  assert.equal(first.size, 30);
  assert.equal(second.size, 30);
  assert.equal(third.size, 5);
  assert.equal(new Set(ids).size, 65);
});
