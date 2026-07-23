// Security-assessment PoC + regression suite (sec/security-assessment branch).
//
// These tests assert the SECURE (desired) behaviour for findings F-01..F-03
// from docs/security/SECURITY_ASSESSMENT_ORCHESTRATION_PLAN.md. They are
// written so that:
//   * against the PRE-FIX rules they FAIL  -> dynamic confirmation of the bug
//   * against the POST-FIX rules they PASS -> permanent regression guards
//
// Each finding pairs a positive control (a legitimate write that must keep
// working) with the malicious write that must be denied, so a red test
// isolates to the vulnerability and not to a seeding/permission mistake.
//
// Runs against the Firebase Emulator only, synthetic data only:
//   ../scripts/with-jdk21.sh firebase emulators:exec --config ../firebase.deletion.json \
//     --only firestore --project demo-lumi-secpoc \
//     "node --test test/security_poc.rules.test.js"

const path = require('path');
const fs = require('fs');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'demo-lumi-secpoc';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

const FUTURE = new Date(Date.now() + 365 * 24 * 3600 * 1000);

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

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

function seedData(seedFn) {
  return testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

function authDb(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

// ─── F-01 ────────────────────────────────────────────────────────────────
// Student `create` must not accept the server-owned `access` entitlement map
// (nor autoAward/parentIds/etc.). The `update` path blocks these; `create`
// omitted the guard, so a schoolAdmin/teacher could mint a student that is
// entitlement-live from creation, bypassing `studentAccessLive`.
test('F-01 students.create: staff cannot seed a forged access map (or other server-owned fields)', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('admin_1')
      .set({ role: 'schoolAdmin', schoolId: 'school_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1')
      .set({ role: 'teacher', schoolId: 'school_1' });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_1')
      .set({ schoolId: 'school_1', teacherId: 'teacher_1', teacherIds: ['teacher_1'], studentIds: [] });
  });

  const studentsCol = (db) =>
    db.collection('schools').doc('school_1').collection('students');

  // Positive control: a legitimate student create (no server-owned fields) succeeds.
  await assertSucceeds(studentsCol(authDb('admin_1')).doc('legit_1').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'Ava', lastName: 'Reed',
    currentReadingLevel: 'A', isActive: true, createdAt: new Date(),
  }));

  // F-01a: admin creating a student pre-seeded with a live access map -> DENIED.
  await assertFails(studentsCol(authDb('admin_1')).doc('evil_admin').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'X', lastName: 'Y',
    isActive: true, createdAt: new Date(),
    access: { status: 'active', expiresAt: FUTURE },
  }));

  // F-01b: teacher-of-class doing the same -> DENIED.
  await assertFails(studentsCol(authDb('teacher_1')).doc('evil_teacher').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'X', lastName: 'Y',
    isActive: true, createdAt: new Date(),
    access: { status: 'active', expiresAt: FUTURE },
  }));

  // F-01c: other server-owned fields on create -> DENIED.
  await assertFails(studentsCol(authDb('admin_1')).doc('evil_award').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'X', lastName: 'Y',
    isActive: true, createdAt: new Date(),
    autoAward: { characterId: 'gold_lumi', name: 'Reader of the Week' },
  }));
  await assertFails(studentsCol(authDb('admin_1')).doc('evil_parent').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'X', lastName: 'Y',
    isActive: true, createdAt: new Date(),
    parentIds: ['smuggled_parent'],
  }));

  // manualAward stays teacher-writable on create (parity with the update rule).
  await assertSucceeds(studentsCol(authDb('teacher_1')).doc('ok_award').set({
    schoolId: 'school_1', classId: 'class_1', firstName: 'Ok', lastName: 'Award',
    isActive: true, createdAt: new Date(),
    manualAward: { characterId: 'special_lumi', name: 'Star Reader', awardedBy: 'teacher_1' },
  }));
});

// ─── F-02 ────────────────────────────────────────────────────────────────
// School `create` must not accept server-owned commercial/provisioning fields
// (subscription/access/accessMode/isDemo). The `update` path blocks them via
// schoolCommercialFieldsUnchanged(); `create` omitted the guard.
test('F-02 schools.create: creator cannot seed commercial/provisioning fields', async () => {
  const schools = (db) => db.collection('schools');

  // Positive control: a plain school create by its creator succeeds.
  await assertSucceeds(schools(authDb('founder_1')).doc('school_new').set({
    name: 'New School', createdBy: 'founder_1',
  }));

  // F-02a: seeding a live access map on create -> DENIED.
  await assertFails(schools(authDb('founder_2')).doc('school_evil').set({
    name: 'Evil School', createdBy: 'founder_2',
    access: { status: 'active', expiresAt: FUTURE },
  }));

  // F-02b: seeding subscription/accessMode/isDemo on create -> DENIED.
  await assertFails(schools(authDb('founder_3')).doc('school_evil2').set({
    name: 'Evil School 2', createdBy: 'founder_3',
    subscription: { status: 'active' }, accessMode: 'whole_school_paid', isDemo: true,
  }));
});

// ─── F-03 ────────────────────────────────────────────────────────────────
// Class `update` authorised a teacher-of-class with no field restriction, so a
// teacher could reassign ownership (teacherId/teacherIds) — hand the class to an
// attacker uid or remove themselves. schoolAdmin retains full control.
test('F-03 classes.update: a teacher cannot reassign class ownership', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1')
      .set({ role: 'teacher', schoolId: 'school_1' });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_1').set({
      schoolId: 'school_1', name: '3A', teacherId: 'teacher_1', teacherIds: ['teacher_1'],
      studentIds: [], isActive: true, createdBy: 'teacher_1',
    });
  });

  const classRef = (db) =>
    db.collection('schools').doc('school_1').collection('classes').doc('class_1');

  // Positive control: the class teacher can still edit award settings.
  await assertSucceeds(
    classRef(authDb('teacher_1')).update({ 'settings.awards.topReader.enabled': true }),
  );

  // F-03a: teacher hands ownership to an attacker uid -> DENIED.
  await assertFails(
    classRef(authDb('teacher_1')).update({ teacherId: 'attacker', teacherIds: ['attacker'] }),
  );

  // F-03b: teacher swaps the owners list (removing self) -> DENIED.
  await assertFails(
    classRef(authDb('teacher_1')).update({ teacherIds: ['attacker'] }),
  );
});
