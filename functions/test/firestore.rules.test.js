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

test('books: teacher can read and write school-scoped books', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School One', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher', schoolId: 'school_1',
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertSucceeds(
    teacherDb.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').set({
      title: 'Test Book', isbn: '9780123456786', isbnNormalized: '9780123456786',
      schoolId: 'school_1', metadata: { source: 'test' },
    }),
  );

  await assertSucceeds(
    teacherDb.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').get(),
  );
});

test('books: admin can read and write school-scoped books', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School One', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('admin_1').set({
      role: 'schoolAdmin', schoolId: 'school_1',
    });
  });

  const adminDb = authDb('admin_1');

  await assertSucceeds(
    adminDb.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').set({
      title: 'Admin Book', isbn: '9780123456786', isbnNormalized: '9780123456786',
      schoolId: 'school_1', metadata: { source: 'test' },
    }),
  );
});

test('books: parent can read but NOT write school-scoped books', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School One', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent', schoolId: 'school_1',
    });
    await db.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').set({
      title: 'Test Book', isbn: '9780123456786', isbnNormalized: '9780123456786',
      schoolId: 'school_1', metadata: { source: 'test' },
    });
  });

  const parentDb = authDb('parent_1');

  // Parents can read the school library
  await assertSucceeds(
    parentDb.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').get(),
  );

  // Parents cannot write to the school library
  await assertFails(
    parentDb.collection('schools').doc('school_1').collection('books').doc('isbn_new').set({
      title: 'Parent Book', isbn: '9780000000000', schoolId: 'school_1', metadata: { source: 'test' },
    }),
  );
});

test('books: teacher at different school cannot read or write', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School One', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_2').set({ name: 'Lumi School Two', createdBy: 'admin_2' });
    await db.collection('schools').doc('school_2').collection('users').doc('teacher_2').set({
      role: 'teacher', schoolId: 'school_2',
    });
    await db.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').set({
      title: 'School 1 Book', isbn: '9780123456786', isbnNormalized: '9780123456786',
      schoolId: 'school_1', metadata: { source: 'test' },
    });
  });

  const outsiderDb = authDb('teacher_2');

  await assertFails(
    outsiderDb.collection('schools').doc('school_1').collection('books').doc('isbn_9780123456786').get(),
  );

  await assertFails(
    outsiderDb.collection('schools').doc('school_1').collection('books').doc('isbn_new').set({
      title: 'Outsider Book', isbn: '9780000000000', schoolId: 'school_1', metadata: {},
    }),
  );
});

test('books: teacher cannot write book with mismatched schoolId', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({ name: 'Lumi School One', createdBy: 'admin_1' });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher', schoolId: 'school_1',
    });
  });

  const teacherDb = authDb('teacher_1');

  // Trying to write a book with schoolId pointing to a different school
  await assertFails(
    teacherDb.collection('schools').doc('school_1').collection('books').doc('isbn_spoofed').set({
      title: 'Spoofed Book', isbn: '9780000000000', schoolId: 'school_2', metadata: {},
    }),
  );
});

test('books: legacy top-level books are school-scoped read-only fallback', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 0,
      studentCount: 0,
    });
    await db.collection('schools').doc('school_2').set({
      name: 'Lumi School Two',
      createdBy: 'admin_2',
      teacherCount: 1,
      parentCount: 0,
      studentCount: 0,
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
    });
    await db.collection('schools').doc('school_2').collection('users').doc('teacher_2').set({
      role: 'teacher',
      schoolId: 'school_2',
    });

    await db.collection('books').doc('isbn_9780123456786').set({
      title: 'Legacy Book',
      isbn: '9780123456786',
      isbnNormalized: '9780123456786',
      schoolId: 'school_1',
    });
  });

  const teacherOneDb = authDb('teacher_1');
  const teacherTwoDb = authDb('teacher_2');

  await assertSucceeds(
    teacherOneDb.collection('books').doc('isbn_9780123456786').get(),
  );

  await assertFails(
    teacherTwoDb.collection('books').doc('isbn_9780123456786').get(),
  );

  await assertFails(
    teacherOneDb.collection('books').doc('isbn_9780123456786').update({
      title: 'Should Fail',
    }),
  );
});

test('allocations: teacher can query school allocations', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
    });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
    });
    await db.collection('schools').doc('school_1').collection('allocations').doc('alloc_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      teacherId: 'teacher_1',
      studentIds: ['student_1'],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: 20,
      startDate: new Date('2026-03-09T00:00:00Z'),
      endDate: new Date('2026-03-20T00:00:00Z'),
      createdAt: new Date('2026-03-09T00:00:00Z'),
      createdBy: 'teacher_1',
      isActive: true,
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertSucceeds(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .where('isActive', '==', true)
      .get(),
  );
});

test('allocations: parent can read linked child allocations only', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
    });
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_1').set({
      schoolId: 'school_1',
      name: 'Class One',
      teacherId: 'teacher_1',
      studentIds: ['student_1', 'student_2'],
    });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_2').set({
      schoolId: 'school_1',
      name: 'Class Two',
      teacherId: 'teacher_1',
      studentIds: ['student_9'],
    });
    await db.collection('schools').doc('school_1').collection('allocations').doc('alloc_student_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      teacherId: 'teacher_1',
      studentIds: ['student_1'],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: 20,
      startDate: new Date('2026-03-09T00:00:00Z'),
      endDate: new Date('2026-03-20T00:00:00Z'),
      createdAt: new Date('2026-03-09T00:00:00Z'),
      createdBy: 'teacher_1',
      isActive: true,
    });
    await db.collection('schools').doc('school_1').collection('allocations').doc('alloc_class_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      teacherId: 'teacher_1',
      studentIds: [],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: 20,
      startDate: new Date('2026-03-09T00:00:00Z'),
      endDate: new Date('2026-03-20T00:00:00Z'),
      createdAt: new Date('2026-03-09T00:00:00Z'),
      createdBy: 'teacher_1',
      isActive: true,
    });
    await db.collection('schools').doc('school_1').collection('allocations').doc('alloc_other_student').set({
      schoolId: 'school_1',
      classId: 'class_2',
      teacherId: 'teacher_1',
      studentIds: ['student_9'],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: 20,
      startDate: new Date('2026-03-09T00:00:00Z'),
      endDate: new Date('2026-03-20T00:00:00Z'),
      createdAt: new Date('2026-03-09T00:00:00Z'),
      createdBy: 'teacher_1',
      isActive: true,
    });
    await db.collection('schools').doc('school_1').collection('allocations').doc('alloc_other_class').set({
      schoolId: 'school_1',
      classId: 'class_2',
      teacherId: 'teacher_1',
      studentIds: [],
      type: 'byTitle',
      cadence: 'weekly',
      targetMinutes: 20,
      startDate: new Date('2026-03-09T00:00:00Z'),
      endDate: new Date('2026-03-20T00:00:00Z'),
      createdAt: new Date('2026-03-09T00:00:00Z'),
      createdBy: 'teacher_1',
      isActive: true,
    });
  });

  const parentDb = authDb('parent_1');

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .where('studentIds', 'array-contains', 'student_1')
      .where('isActive', '==', true)
      .get(),
  );

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .where('classId', '==', 'class_1')
      .where('studentIds', '==', [])
      .where('isActive', '==', true)
      .get(),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .doc('alloc_other_student')
      .get(),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .where('classId', '==', 'class_2')
      .where('studentIds', '==', [])
      .where('isActive', '==', true)
      .get(),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('allocations')
      .where('isActive', '==', true)
      .get(),
  );
});

test('readingLevelEvents: teacher can create and read student level history', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 1,
      studentCount: 1,
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
      fullName: 'Teacher One',
    });

    await db.collection('schools').doc('school_1').collection('students').doc('student_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      firstName: 'Emma',
      lastName: 'Wilson',
      currentReadingLevel: 'A',
      isActive: true,
      createdAt: new Date(),
    });

    await db.collection('schools').doc('school_1').collection('students').doc('student_1').collection('readingLevelEvents').doc('event_seed').set({
      studentId: 'student_1',
      schoolId: 'school_1',
      classId: 'class_1',
      fromLevel: 'A',
      toLevel: 'B',
      source: 'teacher',
      changedByUserId: 'teacher_1',
      changedByRole: 'teacher',
      changedByName: 'Teacher One',
      createdAt: new Date(),
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertSucceeds(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .collection('readingLevelEvents')
      .doc('event_new')
      .set({
        studentId: 'student_1',
        schoolId: 'school_1',
        classId: 'class_1',
        fromLevel: 'B',
        toLevel: 'C',
        source: 'teacher',
        changedByUserId: 'teacher_1',
        changedByRole: 'teacher',
        changedByName: 'Teacher One',
        createdAt: new Date(),
      }),
  );

  await assertSucceeds(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .collection('readingLevelEvents')
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get(),
  );
});

test('students: teacher can update student reading level fields', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 1,
      studentCount: 1,
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
      fullName: 'Teacher One',
    });

    await db.collection('schools').doc('school_1').collection('students').doc('student_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      firstName: 'Emma',
      lastName: 'Wilson',
      currentReadingLevel: 'A',
      currentReadingLevelIndex: 0,
      isActive: true,
      createdAt: new Date(),
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertSucceeds(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .update({
        currentReadingLevel: 'B',
        currentReadingLevelIndex: 1,
        readingLevelUpdatedBy: 'teacher_1',
        readingLevelSource: 'teacher',
        readingLevelUpdatedAt: new Date(),
      }),
  );
});

test('readingLevelEvents: parent cannot read staff-only student level history', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 1,
      studentCount: 1,
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });

    await db.collection('schools').doc('school_1').collection('students').doc('student_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      firstName: 'Emma',
      lastName: 'Wilson',
      currentReadingLevel: 'B',
      isActive: true,
      createdAt: new Date(),
    });

    await db.collection('schools').doc('school_1').collection('students').doc('student_1').collection('readingLevelEvents').doc('event_seed').set({
      studentId: 'student_1',
      schoolId: 'school_1',
      classId: 'class_1',
      fromLevel: 'A',
      toLevel: 'B',
      source: 'teacher',
      changedByUserId: 'teacher_1',
      changedByRole: 'teacher',
      changedByName: 'Teacher One',
      createdAt: new Date(),
    });
  });

  const parentDb = authDb('parent_1');

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .collection('readingLevelEvents')
      .doc('event_seed')
      .get(),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('students')
      .doc('student_1')
      .collection('readingLevelEvents')
      .orderBy('createdAt', 'desc')
      .limit(10)
      .get(),
  );
});

test('notificationCampaigns: teacher can read own campaign but not create or read others', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
    });

    await db.collection('schools').doc('school_1').collection('users').doc('admin_1').set({
      role: 'schoolAdmin',
      schoolId: 'school_1',
    });

    await db.collection('schools').doc('school_1').collection('notificationCampaigns').doc('campaign_teacher').set({
      schoolId: 'school_1',
      createdBy: 'teacher_1',
      createdByRole: 'teacher',
      title: 'Teacher reminder',
      body: 'Bring your readers back tomorrow.',
      messageType: 'reading_reminder',
      audienceType: 'classes',
      targetClassIds: ['class_1'],
      targetStudentIds: [],
      status: 'sent',
      createdAt: new Date(),
    });

    await db.collection('schools').doc('school_1').collection('notificationCampaigns').doc('campaign_admin').set({
      schoolId: 'school_1',
      createdBy: 'admin_1',
      createdByRole: 'schoolAdmin',
      title: 'Admin reminder',
      body: 'Whole school reminder.',
      messageType: 'announcement',
      audienceType: 'school',
      targetClassIds: [],
      targetStudentIds: [],
      status: 'sent',
      createdAt: new Date(),
    });
  });

  const teacherDb = authDb('teacher_1');
  const adminDb = authDb('admin_1');

  await assertSucceeds(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('notificationCampaigns')
      .doc('campaign_teacher')
      .get(),
  );

  await assertFails(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('notificationCampaigns')
      .doc('campaign_admin')
      .get(),
  );

  await assertFails(
    teacherDb
      .collection('schools')
      .doc('school_1')
      .collection('notificationCampaigns')
      .doc('campaign_new')
      .set({
        schoolId: 'school_1',
        createdBy: 'teacher_1',
        title: 'Blocked create',
      }),
  );

  await assertSucceeds(
    adminDb
      .collection('schools')
      .doc('school_1')
      .collection('notificationCampaigns')
      .doc('campaign_admin')
      .get(),
  );
});

test('parent notifications: parent can read and mark own inbox items read only', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_2').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: [],
    });

    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').collection('notifications').doc('campaign_1').set({
      campaignId: 'campaign_1',
      schoolId: 'school_1',
      title: 'Reminder',
      body: 'Bring your books back tomorrow.',
      messageType: 'reading_reminder',
      studentIds: ['student_1'],
      classIds: ['class_1'],
      senderName: 'Teacher One',
      senderRole: 'teacher',
      pushStatus: 'sent',
      isRead: false,
      readAt: null,
      createdAt: new Date(),
      deliveredAt: new Date(),
    });
  });

  const parentDb = authDb('parent_1');
  const otherParentDb = authDb('parent_2');

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .get(),
  );

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .get(),
  );

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .update({
        isRead: true,
        readAt: new Date(),
      }),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .update({
        title: 'Tampered',
      }),
  );

  await assertFails(
    otherParentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .get(),
  );

  await assertFails(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_2')
      .set({
        campaignId: 'campaign_2',
        schoolId: 'school_1',
      }),
  );
});

test('legacy top-level notifications are blocked for clients', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
    });

    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
    });

    await db.collection('notifications').doc('legacy_1').set({
      schoolId: 'school_1',
      userId: 'teacher_1',
    });
  });

  const teacherDb = authDb('teacher_1');

  await assertFails(
    teacherDb.collection('notifications').doc('legacy_1').get(),
  );

  await assertFails(
    teacherDb.collection('notifications').doc('legacy_2').set({
      schoolId: 'school_1',
      userId: 'teacher_1',
    }),
  );
});

test('sanity: test environment initialized', async () => {
  assert.ok(testEnv);
});
