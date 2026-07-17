const path = require('node:path');
const fs = require('node:fs');
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
      }
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

    assert.equal(weekly.size, studentCount * DAYS);
    assert.equal(recent.size, 15);
    results.push({
      students: studentCount,
      seededWeeklyLogs: weekly.size,
      weeklyQueryMs: weeklyMs,
      recentReads: recent.size,
      recentQueryMs: recentMs,
      projectedTwelveWeekCalendarReads: studentCount * 84,
    });
  }
  console.log(`SCALE_EVIDENCE ${JSON.stringify(results)}`);
});
