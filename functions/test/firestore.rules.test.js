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

// ────────────────────────────────────────────────────────────────────────────
// Developer impersonation: read-only real-school access via custom claims.
// Phase 1 of the impersonation pipeline. See firestore.rules helpers
// `isDevImpersonating()`, `isDevImpersonatingSchool(schoolId)`, and
// `writeAllowedForDev()`, plus the new collections:
//   - devImpersonationSessions
//   - devImpersonationAudit
//   - devImpersonationRateLimits
//   - superAdmins
// ────────────────────────────────────────────────────────────────────────────

const SCHOOL_A = 'school_a';
const SCHOOL_B = 'school_b';
const DEV_UID = 'dev_user_1';
const DEV_EMAIL = 'dev@lumi.app';
const TEACHER_A_UID = 'teacher_a_1';
const TEACHER_B_UID = 'teacher_b_1';
const STUDENT_A_ID = 'student_a_1';
const STUDENT_B_ID = 'student_b_1';
const CLASS_A_ID = 'class_a_1';
const SESSION_ID = 'sess_abc';

function impersonationClaims(overrides = {}) {
  return {
    devImpersonating: true,
    impersonationSchoolId: SCHOOL_A,
    impersonationUserId: TEACHER_A_UID,
    impersonationRole: 'teacher',
    impersonationSessionId: SESSION_ID,
    devReadOnly: true,
    devUid: DEV_UID,
    devEmail: DEV_EMAIL,
    ...overrides,
  };
}

async function seedTwoSchools() {
  await seedData(async (db) => {
    await db.collection('schools').doc(SCHOOL_A).set({
      name: 'Lumi A',
      createdBy: 'admin_a',
      teacherCount: 1,
      parentCount: 0,
      studentCount: 1,
    });
    await db.collection('schools').doc(SCHOOL_B).set({
      name: 'Lumi B',
      createdBy: 'admin_b',
      teacherCount: 1,
      parentCount: 0,
      studentCount: 1,
    });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('users').doc(TEACHER_A_UID).set({
        email: 'teacher_a@lumi.app',
        fullName: 'Teacher A',
        role: 'teacher',
        schoolId: SCHOOL_A,
        isActive: true,
      });
    await db
      .collection('schools').doc(SCHOOL_B)
      .collection('users').doc(TEACHER_B_UID).set({
        email: 'teacher_b@lumi.app',
        fullName: 'Teacher B',
        role: 'teacher',
        schoolId: SCHOOL_B,
        isActive: true,
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('students').doc(STUDENT_A_ID).set({
        firstName: 'A',
        lastName: 'Student',
        schoolId: SCHOOL_A,
        classId: CLASS_A_ID,
        parentIds: [],
      });
    await db
      .collection('schools').doc(SCHOOL_B)
      .collection('students').doc(STUDENT_B_ID).set({
        firstName: 'B',
        lastName: 'Student',
        schoolId: SCHOOL_B,
        classId: 'class_b_1',
        parentIds: [],
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('classes').doc(CLASS_A_ID).set({
        name: 'Class A',
        schoolId: SCHOOL_A,
        teacherId: TEACHER_A_UID,
        teacherIds: [TEACHER_A_UID],
        studentIds: [STUDENT_A_ID],
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('allocations').doc('alloc_a_1').set({
        schoolId: SCHOOL_A,
        teacherId: TEACHER_A_UID,
        classId: CLASS_A_ID,
        studentIds: [STUDENT_A_ID],
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('readingLogs').doc('log_a_1').set({
        schoolId: SCHOOL_A,
        studentId: STUDENT_A_ID,
        parentId: 'parent_a_1',
        minutesRead: 10,
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('books').doc('book_a_1').set({
        schoolId: SCHOOL_A,
        title: 'Book A',
      });
    await db
      .collection('schools').doc(SCHOOL_A)
      .collection('readingGroups').doc('rg_a_1').set({
        schoolId: SCHOOL_A,
        name: 'Group A',
      });
  });
}

// ── Reads ──────────────────────────────────────────────────────────────────

test('impersonation: dev with claim reads target-school student', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: dev without claim cannot read target-school student', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID);
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: claim for school_a cannot read school_b student', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims({ impersonationSchoolId: SCHOOL_A }));
  await assertFails(
    db.collection('schools').doc(SCHOOL_B).collection('students').doc(STUDENT_B_ID).get(),
  );
});

test('impersonation: dev can list students in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('students').get(),
  );
});

test('impersonation: dev can read classes in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('classes').doc(CLASS_A_ID).get(),
  );
});

test('impersonation: dev can read allocations in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('allocations').doc('alloc_a_1').get(),
  );
});

test('impersonation: dev can read reading logs in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('readingLogs').doc('log_a_1').get(),
  );
});

test('impersonation: dev can read books in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('books').doc('book_a_1').get(),
  );
});

test('impersonation: dev can read reading groups in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('readingGroups').doc('rg_a_1').get(),
  );
});

test('impersonation: dev can read users collection in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('users').doc(TEACHER_A_UID).get(),
  );
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('users').get(),
  );
});

test('impersonation: dev can read parents collection in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).collection('parents').get(),
  );
});

test('impersonation: missing impersonationSessionId denies reads', async () => {
  await seedTwoSchools();
  const claims = impersonationClaims();
  delete claims.impersonationSessionId;
  const db = authDb(DEV_UID, claims);
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: devImpersonating=false denies reads even with schoolId match', async () => {
  await seedTwoSchools();
  const claims = impersonationClaims({ devImpersonating: false });
  const db = authDb(DEV_UID, claims);
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: dev can read target school top-level doc', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertSucceeds(
    db.collection('schools').doc(SCHOOL_A).get(),
  );
});

// ── Writes must all fail under devReadOnly ────────────────────────────────

test('impersonation: dev cannot create student in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc('new_stud').set({
      firstName: 'X',
      lastName: 'Y',
      schoolId: SCHOOL_A,
      classId: CLASS_A_ID,
      parentIds: [],
    }),
  );
});

test('impersonation: dev cannot update student', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).update({
      firstName: 'Tampered',
    }),
  );
});

test('impersonation: dev cannot delete student', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).delete(),
  );
});

test('impersonation: dev cannot create own user doc in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('users').doc(DEV_UID).set({
      email: DEV_EMAIL,
      fullName: 'Dev',
      role: 'teacher',
      schoolId: SCHOOL_A,
      isActive: true,
    }),
  );
});

test('impersonation: dev cannot create own parent doc in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('parents').doc(DEV_UID).set({
      email: DEV_EMAIL,
      fullName: 'Dev',
      role: 'parent',
      schoolId: SCHOOL_A,
    }),
  );
});

test('impersonation: dev cannot append own uid to student parentIds', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('students').doc(STUDENT_A_ID).update({
      parentIds: [DEV_UID],
    }),
  );
});

test('impersonation: dev cannot create reading log', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('readingLogs').doc('new_log').set({
      schoolId: SCHOOL_A,
      studentId: STUDENT_A_ID,
      parentId: DEV_UID,
      minutesRead: 5,
    }),
  );
});

test('impersonation: dev cannot create class', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('classes').doc('new_class').set({
      schoolId: SCHOOL_A,
      name: 'C',
      teacherId: DEV_UID,
      teacherIds: [DEV_UID],
      studentIds: [],
    }),
  );
});

test('impersonation: dev cannot create allocation', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('allocations').doc('new_alloc').set({
      schoolId: SCHOOL_A,
      classId: CLASS_A_ID,
      studentIds: [STUDENT_A_ID],
    }),
  );
});

test('impersonation: dev cannot create book in target school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('books').doc('new_book').set({
      schoolId: SCHOOL_A,
      title: 'New',
    }),
  );
});

test('impersonation: dev cannot create reading group', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A).collection('readingGroups').doc('new_rg').set({
      schoolId: SCHOOL_A,
      name: 'RG',
    }),
  );
});

test('impersonation: dev cannot create a new school', async () => {
  await seedTwoSchools();
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc('new_school').set({
      name: 'New',
      createdBy: DEV_UID,
      teacherCount: 0,
      parentCount: 0,
      studentCount: 0,
    }),
  );
});

test('impersonation: dev cannot create community_books entry', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('community_books').doc('9780000000000').set({
      contributedBy: DEV_UID,
      contributedBySchoolId: SCHOOL_A,
      title: 'X',
    }),
  );
});

test('impersonation: dev cannot submit feedback', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('feedback').doc('fb').set({
      userId: DEV_UID,
      message: 'hi',
    }),
  );
});

test('impersonation: dev cannot create schoolOnboarding doc', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schoolOnboarding').doc('ob_1').set({
      contactEmail: DEV_EMAIL,
      schoolName: 'X',
    }),
  );
});

test('impersonation: dev cannot write top-level users/{uid}', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('users').doc(DEV_UID).set({ name: 'x' }),
  );
});

test('impersonation: dev cannot write userSchoolIndex', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('userSchoolIndex').doc('hash_x').set({
      userId: DEV_UID,
      schoolId: SCHOOL_A,
    }),
  );
});

test('impersonation: devReadOnly claim alone (no impersonating flag) still blocks writes', async () => {
  const db = authDb(DEV_UID, { devReadOnly: true });
  await assertFails(
    db.collection('users').doc(DEV_UID).set({ name: 'x' }),
  );
});

// ── New collections: clients are fully locked out ─────────────────────────

test('impersonation collections: dev cannot read own audit events', async () => {
  await seedData(async (db) => {
    await db.collection('devImpersonationAudit').doc('evt_1').set({
      sessionId: SESSION_ID,
      devUid: DEV_UID,
      eventType: 'session_started',
    });
  });
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('devImpersonationAudit').doc('evt_1').get(),
  );
});

test('impersonation collections: dev cannot list sessions', async () => {
  await seedData(async (db) => {
    await db.collection('devImpersonationSessions').doc(SESSION_ID).set({
      devUid: DEV_UID,
      status: 'active',
    });
  });
  const db = authDb(DEV_UID);
  await assertFails(db.collection('devImpersonationSessions').get());
});

test('impersonation collections: dev can get their own session', async () => {
  await seedData(async (db) => {
    await db.collection('devImpersonationSessions').doc(SESSION_ID).set({
      devUid: DEV_UID,
      status: 'active',
    });
  });
  const db = authDb(DEV_UID);
  await assertSucceeds(
    db.collection('devImpersonationSessions').doc(SESSION_ID).get(),
  );
});

test("impersonation collections: dev cannot get another dev's session", async () => {
  await seedData(async (db) => {
    await db.collection('devImpersonationSessions').doc('other_sess').set({
      devUid: 'other_dev',
      status: 'active',
    });
  });
  const db = authDb(DEV_UID);
  await assertFails(
    db.collection('devImpersonationSessions').doc('other_sess').get(),
  );
});

test('impersonation collections: no one can read superAdmins', async () => {
  await seedData(async (db) => {
    await db.collection('superAdmins').doc('me').set({ since: new Date() });
  });
  await assertFails(authDb('me').collection('superAdmins').doc('me').get());
  await assertFails(unauthDb().collection('superAdmins').doc('me').get());
});

test('impersonation collections: no one can write superAdmins', async () => {
  await assertFails(
    authDb('me').collection('superAdmins').doc('me').set({ since: new Date() }),
  );
});

test('impersonation collections: no one can write rate-limit counters', async () => {
  const db = authDb(DEV_UID);
  await assertFails(
    db.collection('devImpersonationRateLimits').doc(DEV_UID).set({ hourCount: 0 }),
  );
});

test('impersonation collections: no one can write audit events directly', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('devImpersonationAudit').doc('evt_x').set({ eventType: 'fake' }),
  );
});

test('impersonation collections: no one can write sessions directly', async () => {
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('devImpersonationSessions').doc('fake').set({
      devUid: DEV_UID,
      status: 'active',
    }),
  );
});
