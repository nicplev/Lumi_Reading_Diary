const path = require('path');
const fs = require('fs');
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'lumi-reading-tracker-rules-test';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');

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

async function seedData(seedFn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await seedFn(context.firestore());
  });
}

function authDb(uid, token = {}) {
  return testEnv.authenticatedContext(uid, token).firestore();
}

function unauthDb() {
  return testEnv.unauthenticatedContext().firestore();
}

test('schoolCodes: unauthenticated validation query is bounded to limit(1)', async () => {
  await seedData(async (db) => {
    await db.collection('schoolCodes').doc('code_1').set({
      code: 'ABC123',
      schoolId: 'school_1',
      schoolName: 'Lumi School',
      usageCount: 0,
      createdBy: 'admin_1',
      isActive: true,
      createdAt: new Date(),
    });
  });

  await assertSucceeds(
    unauthDb().collection('schoolCodes').where('code', '==', 'ABC123').limit(1).get(),
  );

  await assertFails(
    unauthDb().collection('schoolCodes').where('code', '==', 'ABC123').limit(2).get(),
  );
});

test('users: teacher can create only own profile doc', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 0,
      parentCount: 0,
      studentCount: 0,
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertSucceeds(
    teacherDb.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      email: 'teacher@example.com',
      fullName: 'Teacher One',
      role: 'teacher',
      schoolId: 'school_1',
      createdAt: new Date(),
      isActive: true,
    }),
  );

  await assertFails(
    teacherDb.collection('schools').doc('school_1').collection('users').doc('teacher_2').set({
      email: 'other@example.com',
      fullName: 'Teacher Two',
      role: 'teacher',
      schoolId: 'school_1',
      createdAt: new Date(),
      isActive: true,
    }),
  );
});

test('parents: parent can create only own profile doc', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 0,
      parentCount: 0,
      studentCount: 0,
    });
  });

  const parentDb = authDb('parent_1');

  await assertSucceeds(
    parentDb.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      email: 'parent@example.com',
      fullName: 'Parent One',
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: [],
      createdAt: new Date(),
      isActive: true,
    }),
  );

  await assertFails(
    parentDb.collection('schools').doc('school_1').collection('parents').doc('parent_2').set({
      email: 'other-parent@example.com',
      fullName: 'Parent Two',
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: [],
      createdAt: new Date(),
      isActive: true,
    }),
  );
});

test('school counters: only role-aligned increments are allowed', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 1,
      studentCount: 10,
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: [],
    });
  });

  const teacherDb = authDb('teacher_1');
  const parentDb = authDb('parent_1');

  await assertSucceeds(
    teacherDb.collection('schools').doc('school_1').update({
      teacherCount: 2,
    }),
  );

  await assertFails(
    teacherDb.collection('schools').doc('school_1').update({
      parentCount: 2,
    }),
  );

  await assertSucceeds(
    parentDb.collection('schools').doc('school_1').update({
      parentCount: 2,
    }),
  );
});

test('studentLinkCodes: parent verification query is bounded and role writes are enforced', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 1,
      studentCount: 10,
    });

    await db.collection('schools').doc('school_1').collection('users').doc('admin_1').set({
      role: 'schoolAdmin',
      schoolId: 'school_1',
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });

    await db.collection('studentLinkCodes').doc('code_doc_1').set({
      code: 'ZXCV1234',
      schoolId: 'school_1',
      studentId: 'student_1',
      status: 'active',
      createdBy: 'admin_1',
      createdAt: new Date(),
      expiresAt: new Date(Date.now() + 86400000),
    });
  });

  await assertSucceeds(
    unauthDb().collection('studentLinkCodes').where('code', '==', 'ZXCV1234').limit(10).get(),
  );

  await assertFails(
    unauthDb().collection('studentLinkCodes').where('code', '==', 'ZXCV1234').limit(11).get(),
  );

  const parentDb = authDb('parent_1');

  await assertSucceeds(
    parentDb.collection('studentLinkCodes').doc('code_doc_1').update({
      status: 'used',
      usedBy: 'parent_1',
      usedAt: new Date(),
    }),
  );
});

test('schoolOnboarding: admin can claim ownership during first setup update', async () => {
  await seedData(async (db) => {
    await db.collection('schoolOnboarding').doc('onboarding_1').set({
      schoolName: 'Lumi School',
      contactEmail: 'owner@school.test',
      status: 'demo',
      currentStep: 'schoolInfo',
      createdAt: new Date(),
      adminUserId: null,
    });
  });

  const adminDb = authDb('admin_1', { email: 'admin@school.test' });

  await assertSucceeds(
    adminDb.collection('schoolOnboarding').doc('onboarding_1').update({
      adminUserId: 'admin_1',
      status: 'registered',
    }),
  );

  const otherDb = authDb('other_1', { email: 'other@school.test' });
  await assertFails(
    otherDb.collection('schoolOnboarding').doc('onboarding_1').update({
      status: 'active',
    }),
  );
});

test('sanity: test environment initialized', async () => {
  assert.ok(testEnv);
});
