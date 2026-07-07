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

test('schoolCodes: unauthenticated reads are denied (verification is server-side)', async () => {
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

  // The old bounded unauthenticated `list` rule is gone — verification now
  // goes through the verifySchoolCode callable. Both the exact-code query and
  // a filter-less pagination attempt must be denied.
  await assertFails(
    unauthDb().collection('schoolCodes').where('code', '==', 'ABC123').limit(1).get(),
  );

  await assertFails(
    unauthDb().collection('schoolCodes').limit(1).get(),
  );
});

test('users: self-provision as teacher is denied (1.3)', async () => {
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

  // Self-create of a teacher user doc is DENIED (1.3). The legitimate teacher
  // signup writes this doc server-side (finalizeTeacher, Admin SDK) after
  // validating a school code. Self-provisioning was the "become a teacher of
  // any school → isTeacher() reads the self-authored doc → all children's PII"
  // escalation.
  await assertFails(
    teacherDb.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      email: 'teacher@example.com',
      fullName: 'Teacher One',
      role: 'teacher',
      schoolId: 'school_1',
      createdAt: new Date(),
      isActive: true,
    }),
  );

  // And of course cannot create anyone else's doc either.
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

test('students: a parent-doc holder cannot self-append to parentIds (1.3)', async () => {
  // Before 1.3, any account with a parent doc in the school could append its own
  // UID to ANY student's parentIds (gated only on "has a parent doc", not a
  // valid link code). That client path was removed — parentIds is written only
  // by the linkParentToStudent callable (Admin SDK). Prove the client write is
  // now denied even for a legitimate parent member.
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 0,
      parentCount: 1,
      studentCount: 1,
    });
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      fullName: 'Parent One',
      linkedChildren: [],
    });
    await db.collection('schools').doc('school_1').collection('students').doc('student_1').set({
      schoolId: 'school_1',
      classId: 'class_1',
      firstName: 'Emma',
      lastName: 'Wilson',
      parentIds: [],
    });
  });

  await assertFails(
    authDb('parent_1')
      .collection('schools').doc('school_1')
      .collection('students').doc('student_1')
      .update({ parentIds: ['parent_1'] }),
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

test('users self-update: whitelisted fields succeed, sensitive fields fail', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 1,
      parentCount: 0,
      studentCount: 0,
    });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
      fullName: 'Teacher One',
    });
  });

  const teacherDb = authDb('teacher_1');
  const userRef = teacherDb.collection('schools').doc('school_1').collection('users').doc('teacher_1');

  await assertSucceeds(userRef.update({ preferences: { theme: 'dark' } }));
  await assertSucceeds(userRef.update({ fcmToken: 'token-abc' }));
  await assertSucceeds(userRef.update({ lastLoginAt: new Date() }));

  // Sensitive / server-owned fields must be rejected on self-update.
  await assertFails(userRef.update({ subscriptionTier: 'pro' }));
  await assertFails(userRef.update({ rateLimit: 1000 }));
  await assertFails(userRef.update({ quota: { reads: 5000 } }));
  await assertFails(userRef.update({ stripeCustomerId: 'cus_x' }));
  await assertFails(userRef.update({ permissions: { admin: true } }));
  await assertFails(userRef.update({ isActive: false }));
  // Allowed field bundled with a sensitive one — whole write rejected.
  await assertFails(userRef.update({ preferences: { theme: 'dark' }, subscriptionTier: 'pro' }));
});

test('parents self-update: whitelisted fields succeed, sensitive fields fail', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School',
      createdBy: 'admin_1',
      teacherCount: 0,
      parentCount: 1,
      studentCount: 0,
    });
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      fullName: 'Parent One',
      linkedChildren: [],
    });
  });

  const parentDb = authDb('parent_1');
  const parentRef = parentDb.collection('schools').doc('school_1').collection('parents').doc('parent_1');

  await assertSucceeds(parentRef.update({ preferences: { reminderTime: '19:00' } }));
  await assertSucceeds(parentRef.update({ relationshipLabel: 'Mum' }));
  await assertSucceeds(parentRef.update({ fcmToken: 'token-xyz' }));

  // Parent must not be able to grant themselves entitlements or alter linking.
  await assertFails(parentRef.update({ subscriptionStatus: 'active' }));
  await assertFails(parentRef.update({ isPremium: true }));
  await assertFails(parentRef.update({ rateLimitOverride: 99999 }));
  await assertFails(parentRef.update({ linkedChildren: ['student_smuggled'] }));
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

  // The old bounded unauthenticated `list` rule is gone — verification now
  // goes through the verifyStudentLinkCode callable. Both the exact-code query
  // and a filter-less pagination attempt (the enumeration vector) must be
  // denied to anonymous callers.
  await assertFails(
    unauthDb().collection('studentLinkCodes').where('code', '==', 'ZXCV1234').limit(10).get(),
  );

  await assertFails(
    unauthDb().collection('studentLinkCodes').limit(10).get(),
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

test('schoolOnboarding: anonymous demo create is shape-validated', async () => {
  const anon = unauthDb();

  // A genuine, well-formed demo request from the public form still works
  // (the flow runs before any account exists).
  await assertSucceeds(
    anon.collection('schoolOnboarding').doc('good_1').set({
      schoolName: 'Lumi School',
      contactEmail: 'owner@school.test',
      status: 'demo',
      currentStep: 'schoolInfo',
      createdAt: new Date(),
      adminUserId: null,
    }),
  );

  // Pre-claiming an admin owner is rejected (adminUserId is set later, only by
  // the authenticated ownership-claim update).
  await assertFails(
    anon.collection('schoolOnboarding').doc('bad_admin').set({
      schoolName: 'Lumi School',
      contactEmail: 'owner@school.test',
      status: 'demo',
      createdAt: new Date(),
      adminUserId: 'attacker',
    }),
  );

  // Non-demo status / missing required fields are rejected.
  await assertFails(
    anon.collection('schoolOnboarding').doc('bad_status').set({
      schoolName: 'Lumi School',
      contactEmail: 'owner@school.test',
      status: 'active',
      createdAt: new Date(),
      adminUserId: null,
    }),
  );
  await assertFails(
    anon.collection('schoolOnboarding').doc('bad_shape').set({
      status: 'demo',
      createdAt: new Date(),
      adminUserId: null,
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

test('students: staff cannot write the server-owned access map or parentIds', async () => {
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
    await db.collection('schools').doc('school_1').collection('users').doc('admin_1').set({
      role: 'schoolAdmin',
      schoolId: 'school_1',
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
  });

  const studentRef = (db) =>
    db.collection('schools').doc('school_1').collection('students').doc('student_1');

  // Self-granting the entitlement is denied for BOTH teacher and admin — access
  // is written only server-side (buildStudentAccess via Admin SDK).
  await assertFails(
    studentRef(authDb('teacher_1')).update({
      access: { status: 'active', expiresAt: new Date(Date.now() + 31536000000) },
    }),
  );
  await assertFails(
    studentRef(authDb('admin_1')).update({ access: { status: 'active' } }),
  );

  // parentIds is owned by the linking system, not free-form staff writes.
  await assertFails(
    studentRef(authDb('teacher_1')).update({ parentIds: ['smuggled_parent'] }),
  );

  // A normal profile / reading-level edit still succeeds.
  await assertSucceeds(
    studentRef(authDb('teacher_1')).update({ currentReadingLevel: 'C' }),
  );

  // manualAward (the teacher's special award) IS a teacher-writable field.
  await assertSucceeds(
    studentRef(authDb('teacher_1')).update({
      manualAward: { characterId: 'special_lumi', name: 'Star Reader', awardedBy: 'teacher_1' },
    }),
  );

  // autoAward (the weekly Top Reader) is server-only — staff cannot spoof it.
  await assertFails(
    studentRef(authDb('teacher_1')).update({
      autoAward: { characterId: 'gold_lumi', name: 'Reader of the Week' },
    }),
  );
  await assertFails(
    studentRef(authDb('admin_1')).update({
      autoAward: { characterId: 'gold_lumi', name: 'Reader of the Week' },
    }),
  );
});

test('classes: teacher of the class can write award settings', async () => {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School', createdBy: 'admin_1',
    });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher', schoolId: 'school_1',
    });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_2').set({
      role: 'teacher', schoolId: 'school_1',
    });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_1').set({
      schoolId: 'school_1', name: '3A', teacherId: 'teacher_1', teacherIds: ['teacher_1'],
      studentIds: [], isActive: true, createdBy: 'teacher_1',
    });
  });

  const classRef = (db) =>
    db.collection('schools').doc('school_1').collection('classes').doc('class_1');

  // The class's own teacher may configure the awards.
  await assertSucceeds(
    classRef(authDb('teacher_1')).update({
      'settings.awards.topReader.enabled': true,
      'settings.awards.topReader.name': 'Reader of the Week',
    }),
  );

  // A teacher who is NOT on this class cannot.
  await assertFails(
    classRef(authDb('teacher_2')).update({ 'settings.awards.special.name': 'Nope' }),
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

  // Only the owning parent can delete inbox items (Clear all / swipe-dismiss).
  await assertFails(
    otherParentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .delete(),
  );

  await assertSucceeds(
    parentDb
      .collection('schools')
      .doc('school_1')
      .collection('parents')
      .doc('parent_1')
      .collection('notifications')
      .doc('campaign_1')
      .delete(),
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

// `session` seeds devImpersonationSessions/{SESSION_ID}. Defaults to an active,
// unexpired session targeting SCHOOL_A (what the rules now require for reads).
// Pass overrides to simulate expired/revoked, or `null` to omit the doc.
async function seedTwoSchools(session = {}) {
  await seedData(async (db) => {
    if (session !== null) {
      await db.collection('devImpersonationSessions').doc(SESSION_ID).set({
        devUid: DEV_UID,
        devEmail: DEV_EMAIL,
        targetSchoolId: SCHOOL_A,
        targetUserId: TEACHER_A_UID,
        status: 'active',
        startedAt: new Date(),
        expiresAt: new Date(Date.now() + 30 * 60 * 1000),
        ...session,
      });
    }
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

// ── Session-doc enforcement: revoke / expiry take effect immediately ─────────

test('impersonation: valid claims but NO session doc denies reads', async () => {
  await seedTwoSchools(null); // omit devImpersonationSessions/{SESSION_ID}
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A)
      .collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: revoked session denies reads despite live claims', async () => {
  await seedTwoSchools({ status: 'revoked' });
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A)
      .collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: expired session denies reads despite live claims', async () => {
  await seedTwoSchools({ expiresAt: new Date(Date.now() - 60 * 1000) });
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A)
      .collection('students').doc(STUDENT_A_ID).get(),
  );
});

test('impersonation: session doc for a different school denies reads', async () => {
  await seedTwoSchools({ targetSchoolId: SCHOOL_B });
  const db = authDb(DEV_UID, impersonationClaims());
  await assertFails(
    db.collection('schools').doc(SCHOOL_A)
      .collection('students').doc(STUDENT_A_ID).get(),
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

// ── Reading log delete (widget-undo banner powers this) ────────────────────

async function seedSchoolWithParentAndLog({ parentUid, otherParentUid }) {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
    });
    await db.collection('schools').doc('school_1').collection('parents').doc(parentUid).set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });
    if (otherParentUid) {
      await db.collection('schools').doc('school_1').collection('parents').doc(otherParentUid).set({
        role: 'parent',
        schoolId: 'school_1',
        linkedChildren: ['student_1'],
      });
    }
    await db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1').set({
      schoolId: 'school_1',
      studentId: 'student_1',
      parentId: parentUid,
      minutesRead: 20,
      status: 'completed',
      bookTitles: ['Reading'],
    });
  });
}

test('readingLogs: parent can delete a log they created (powers widget undo)', async () => {
  await seedSchoolWithParentAndLog({ parentUid: 'parent_1' });
  const db = authDb('parent_1');
  await assertSucceeds(
    db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1').delete(),
  );
});

test('readingLogs: parent cannot delete a log created by a different parent', async () => {
  await seedSchoolWithParentAndLog({ parentUid: 'parent_1', otherParentUid: 'parent_2' });
  const db = authDb('parent_2');
  await assertFails(
    db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1').delete(),
  );
});

test('readingLogs: unauthenticated user cannot delete a log', async () => {
  await seedSchoolWithParentAndLog({ parentUid: 'parent_1' });
  const db = unauthDb();
  await assertFails(
    db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1').delete(),
  );
});

// ── Reading-log comment thread ─────────────────────────────────────────────

async function seedSchoolForComments() {
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
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_outsider').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_999'],
    });
    // A second carer linked to the same student who did NOT create the log.
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_cocarer').set({
      role: 'parent',
      schoolId: 'school_1',
      linkedChildren: ['student_1'],
    });
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_1').set({
      role: 'teacher',
      schoolId: 'school_1',
      classIds: ['class_1'],
    });
    await db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1').set({
      schoolId: 'school_1',
      studentId: 'student_1',
      parentId: 'parent_1',
      minutesRead: 20,
      status: 'completed',
      bookTitles: ['Reading'],
    });
    // A pre-existing teacher comment, to exercise read + immutability.
    await db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1')
      .collection('comments').doc('existing').set({
        authorId: 'teacher_1',
        authorRole: 'teacher',
        authorName: 'Ms Smith',
        body: 'Lovely work',
        studentId: 'student_1',
        parentId: 'parent_1',
        createdAt: new Date(),
      });
  });
}

function commentRef(db, commentId) {
  return db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1')
    .collection('comments').doc(commentId);
}

const parentComment = {
  authorId: 'parent_1',
  authorRole: 'parent',
  authorName: 'Dad',
  body: 'Thank you!',
  studentId: 'student_1',
  parentId: 'parent_1',
  createdAt: new Date(),
};

test('comments: parent of the student can read the thread and post', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_1');
  await assertSucceeds(commentRef(db, 'existing').get());
  await assertSucceeds(commentRef(db, 'p1').set(parentComment));
});

test('comments: teacher can post a teacher comment on any log in the school', async () => {
  await seedSchoolForComments();
  const db = authDb('teacher_1');
  await assertSucceeds(commentRef(db, 't1').set({
    authorId: 'teacher_1',
    authorRole: 'teacher',
    authorName: 'Ms Smith',
    body: 'Great progress',
    studentId: 'student_1',
    parentId: 'parent_1',
    createdAt: new Date(),
  }));
});

test('comments: an unrelated parent cannot read or post', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_outsider');
  await assertFails(commentRef(db, 'existing').get());
  await assertFails(commentRef(db, 'x').set({ ...parentComment, authorId: 'parent_outsider' }));
});

test('comments: authorId cannot be spoofed as another user', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_1');
  await assertFails(commentRef(db, 'spoof').set({ ...parentComment, authorId: 'teacher_1' }));
});

test('comments: a parent cannot post claiming the teacher role', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_1');
  await assertFails(commentRef(db, 'roleswap').set({ ...parentComment, authorRole: 'teacher' }));
});

test('comments: are immutable (no update or delete)', async () => {
  await seedSchoolForComments();
  const db = authDb('teacher_1');
  await assertFails(commentRef(db, 'existing').update({ body: 'edited' }));
  await assertFails(commentRef(db, 'existing').delete());
});

test('comments: unauthenticated user cannot read or post', async () => {
  await seedSchoolForComments();
  const db = unauthDb();
  await assertFails(commentRef(db, 'existing').get());
  await assertFails(commentRef(db, 'u1').set({ ...parentComment, authorId: 'anon' }));
});

function logRef(db) {
  return db.collection('schools').doc('school_1').collection('readingLogs').doc('log_1');
}

test('commentsViewedAt: log owner can mark their own thread read', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_1');
  await assertSucceeds(logRef(db).update({ 'commentsViewedAt.parent_1': new Date() }));
});

test('commentsViewedAt: a linked co-carer who did not create the log can mark their own read marker', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_cocarer');
  await assertSucceeds(logRef(db).update({ 'commentsViewedAt.parent_cocarer': new Date() }));
});

test('commentsViewedAt: a co-carer cannot write another user\'s read marker', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_cocarer');
  await assertFails(logRef(db).update({ 'commentsViewedAt.parent_1': new Date() }));
});

test('commentsViewedAt: a co-carer cannot piggyback an edit to another field', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_cocarer');
  await assertFails(logRef(db).update({
    'commentsViewedAt.parent_cocarer': new Date(),
    minutesRead: 999,
  }));
});

test('commentsViewedAt: a non-owner cannot edit log content via this path', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_cocarer');
  await assertFails(logRef(db).update({ minutesRead: 999 }));
});

test('commentsViewedAt: an unrelated parent cannot mark the thread read', async () => {
  await seedSchoolForComments();
  const db = authDb('parent_outsider');
  await assertFails(logRef(db).update({ 'commentsViewedAt.parent_outsider': new Date() }));
});

// ── platformConfig (platform-wide feature flags) ──────────────────────

const platformFlag = {
  enabled: false,
  updatedAt: new Date(),
  updatedBy: 'super_admin_1',
  updatedByEmail: 'ops@lumi.app',
  reason: 'Cost spike investigation',
};

test('platformConfig: signed-in client can get a flag doc', async () => {
  await seedData(async (db) => {
    await db.collection('platformConfig').doc('comprehensionRecording').set(platformFlag);
  });
  await assertSucceeds(
    authDb('parent_1').collection('platformConfig').doc('comprehensionRecording').get(),
  );
});

test('platformConfig: unauthenticated client cannot get a flag doc', async () => {
  await seedData(async (db) => {
    await db.collection('platformConfig').doc('comprehensionRecording').set(platformFlag);
  });
  await assertFails(
    unauthDb().collection('platformConfig').doc('comprehensionRecording').get(),
  );
});

test('platformConfig: listing is denied even when signed in', async () => {
  await seedData(async (db) => {
    await db.collection('platformConfig').doc('comprehensionRecording').set(platformFlag);
  });
  await assertFails(authDb('parent_1').collection('platformConfig').get());
});

test('platformConfig: clients cannot create, update, or delete flags', async () => {
  await seedData(async (db) => {
    await db.collection('platformConfig').doc('comprehensionRecording').set(platformFlag);
  });
  const db = authDb('parent_1');
  const ref = db.collection('platformConfig').doc('comprehensionRecording');
  await assertFails(ref.update({ enabled: true }));
  await assertFails(ref.delete());
  await assertFails(db.collection('platformConfig').doc('someOtherFlag').set({ enabled: false }));
});

// ── Access entitlement: reading-log create is gated on student.access ───────
// The parent logging path is the single enforcement point. A parent linked to
// the student may create a log ONLY when that student's materialised `access`
// is live (status == 'active' AND expiresAt in the future). Lapsed (expired),
// suspended (unpaid/off-boarded school cascade), and legacy (no access map)
// students are all fail-closed.

const FUTURE = new Date(Date.now() + 365 * 86400000);
const PAST = new Date(Date.now() - 86400000);

async function seedSchoolWithAccessStates() {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
    });
    await db.collection('schools').doc('school_1').collection('parents').doc('parent_1').set({
      role: 'parent',
      schoolId: 'school_1',
      // Linked to every student so the linkedChildren gate always passes and
      // the access check is the only thing that differentiates.
      linkedChildren: [
        'student_active',
        'student_expired',
        'student_suspended',
        'student_legacy',
      ],
    });
    await db.collection('schools').doc('school_1').collection('students').doc('student_active').set({
      schoolId: 'school_1', classId: 'class_1', firstName: 'Ada', lastName: 'A',
      parentIds: ['parent_1'],
      access: { status: 'active', academicYear: 2026, expiresAt: FUTURE, source: 'book_pack_assumed' },
    });
    await db.collection('schools').doc('school_1').collection('students').doc('student_expired').set({
      schoolId: 'school_1', classId: 'class_1', firstName: 'Bea', lastName: 'B',
      parentIds: ['parent_1'],
      access: { status: 'active', academicYear: 2025, expiresAt: PAST, source: 'book_pack_assumed' },
    });
    await db.collection('schools').doc('school_1').collection('students').doc('student_suspended').set({
      schoolId: 'school_1', classId: 'class_1', firstName: 'Cy', lastName: 'C',
      parentIds: ['parent_1'],
      access: { status: 'suspended', academicYear: 2026, expiresAt: FUTURE, source: 'book_pack_assumed' },
    });
    await db.collection('schools').doc('school_1').collection('students').doc('student_legacy').set({
      schoolId: 'school_1', classId: 'class_1', firstName: 'Di', lastName: 'D',
      parentIds: ['parent_1'],
      // No access map — predates the access model.
    });
  });
}

function logFor(db, studentId) {
  return db.collection('schools').doc('school_1').collection('readingLogs').doc(`log_${studentId}`).set({
    schoolId: 'school_1',
    studentId,
    parentId: 'parent_1',
    minutesRead: 20,
    status: 'completed',
    bookTitles: ['Reading'],
  });
}

test('access: parent CAN create a log for a student with live access', async () => {
  await seedSchoolWithAccessStates();
  const db = authDb('parent_1');
  await assertSucceeds(logFor(db, 'student_active'));
});

test('access: parent CANNOT create a log for an expired student', async () => {
  await seedSchoolWithAccessStates();
  const db = authDb('parent_1');
  await assertFails(logFor(db, 'student_expired'));
});

test('access: parent CANNOT create a log for a suspended student', async () => {
  await seedSchoolWithAccessStates();
  const db = authDb('parent_1');
  await assertFails(logFor(db, 'student_suspended'));
});

test('access: parent CANNOT create a log for a legacy student with no access map', async () => {
  await seedSchoolWithAccessStates();
  const db = authDb('parent_1');
  await assertFails(logFor(db, 'student_legacy'));
});

// ── Reading-log minutes bounds ───────────────────────────────────────────────
// Every legit client sends 5-120 minutes; the rules bound 1-240 (matching
// validateReadingLog) so a forged 600-minute log is rejected at the door
// instead of merely being flagged after the fact. Applies to create AND
// content updates (a log could otherwise be created valid, edited to 99999).

function logWithMinutes(db, minutes) {
  return db.collection('schools').doc('school_1').collection('readingLogs').doc('log_bounds').set({
    schoolId: 'school_1',
    studentId: 'student_active',
    parentId: 'parent_1',
    minutesRead: minutes,
    status: 'completed',
    bookTitles: ['Reading'],
  });
}

test('minutes bounds: create with 600 minutes is denied', async () => {
  await seedSchoolWithAccessStates();
  await assertFails(logWithMinutes(authDb('parent_1'), 600));
});

test('minutes bounds: create with 0 minutes is denied', async () => {
  await seedSchoolWithAccessStates();
  await assertFails(logWithMinutes(authDb('parent_1'), 0));
});

test('minutes bounds: create with a string "20" is denied', async () => {
  await seedSchoolWithAccessStates();
  await assertFails(logWithMinutes(authDb('parent_1'), '20'));
});

test('minutes bounds: boundary values 1 and 240 are allowed', async () => {
  await seedSchoolWithAccessStates();
  await assertSucceeds(logWithMinutes(authDb('parent_1'), 1));
  await assertSucceeds(logWithMinutes(authDb('parent_1'), 240));
});

test('minutes bounds: owner cannot edit an existing log up to 600 minutes', async () => {
  await seedSchoolWithAccessStates();
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').collection('readingLogs').doc('log_edit').set({
      schoolId: 'school_1', studentId: 'student_active', parentId: 'parent_1',
      minutesRead: 20, status: 'completed', bookTitles: ['Reading'],
    });
  });
  const db = authDb('parent_1');
  await assertFails(
    db.collection('schools').doc('school_1').collection('readingLogs').doc('log_edit')
      .update({ minutesRead: 600 }),
  );
  // A sane owner edit that keeps minutes in range still works.
  await assertSucceeds(
    db.collection('schools').doc('school_1').collection('readingLogs').doc('log_edit')
      .update({ notes: 'great reading tonight' }),
  );
});

test('access: student reads stay open so the app can render the lapsed screen', async () => {
  await seedSchoolWithAccessStates();
  const db = authDb('parent_1');
  // Even though logging is blocked, the parent can still READ the suspended
  // child's doc to drive the "access lapsed" UI.
  await assertSucceeds(
    db.collection('schools').doc('school_1').collection('students').doc('student_suspended').get(),
  );
});

// Reproduces the offline reading-log drain permission-denied bug. When the
// OfflineService drains an offline-created log, the doc doesn't exist on the
// server yet. A parent GET or UPDATE on a NON-EXISTENT readingLog is DENIED —
// the parent rules dereference `resource.data`, which is null for a missing doc
// (→ permission-denied, not a clean not-found). So `_syncReadingLog`'s
// existence-check get() throws before it reaches the create, and
// `_syncComprehensionAudio`'s update() on the missing log is denied too. The
// CREATE itself is allowed — which is why "tolerate the denied pre-check and go
// straight to create" fixes the drain.
test('readingLogs offline-drain: parent get/update on a NON-EXISTENT log is denied, create is allowed', async () => {
  await seedSchoolWithAccessStates();
  const parentDb = authDb('parent_1');
  const missingRef = parentDb
    .collection('schools').doc('school_1')
    .collection('readingLogs').doc('log_offline_not_yet_synced');

  // 1. The existence-check get() the drain runs first — denied on a missing doc.
  await assertFails(missingRef.get());

  // 2. The comprehension-audio patch — update() on the missing doc — also denied
  //    (the drain only classifies `not-found` as transient, so this surfaces as
  //    permission-denied and blocks the retry).
  await assertFails(missingRef.update({ comprehensionAudioUploaded: true }));

  // 3. But the parent IS allowed to CREATE that same log (linked + live access +
  //    parentId == uid) — so proceeding to create despite the denied pre-check
  //    resolves the drain.
  await assertSucceeds(
    missingRef.set({
      schoolId: 'school_1',
      studentId: 'student_active',
      parentId: 'parent_1',
      minutesRead: 20,
      status: 'completed',
      bookTitles: ['Reading'],
    }),
  );
});

// ── Teacher proxy logs: a teacher logs reading on behalf of a student ────────
// Membership is verified against the CLASS document's teacher assignment, not
// the teacher's denormalised user.classIds (which the portal seeds empty and
// never syncs). The empty `classIds: []` on every teacher doc below is the
// real-world state these tests must succeed in spite of.

async function seedSchoolForTeacherProxy() {
  await seedData(async (db) => {
    await db.collection('schools').doc('school_1').set({
      name: 'Lumi School One',
      createdBy: 'admin_1',
    });
    // Co-teacher assignment via the teacherIds array (the common case).
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_array').set({
      role: 'teacher', schoolId: 'school_1', classIds: [],
    });
    // Owner assignment via the singular teacherId field (legacy/owner case).
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_owner').set({
      role: 'teacher', schoolId: 'school_1', classIds: [],
    });
    // A teacher who teaches a different class entirely.
    await db.collection('schools').doc('school_1').collection('users').doc('teacher_other').set({
      role: 'teacher', schoolId: 'school_1', classIds: [],
    });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_1').set({
      schoolId: 'school_1',
      name: 'Test 1',
      teacherId: 'teacher_owner',
      teacherIds: ['teacher_array'],
      studentIds: ['student_1'],
      isActive: true,
    });
    await db.collection('schools').doc('school_1').collection('classes').doc('class_other').set({
      schoolId: 'school_1',
      name: 'Other',
      teacherIds: ['teacher_other'],
      studentIds: ['student_2'],
      isActive: true,
    });
  });
}

function proxyLog(db, { logId, parentId, classId, loggedByRole = 'teacher' }) {
  return db.collection('schools').doc('school_1').collection('readingLogs').doc(logId).set({
    schoolId: 'school_1',
    studentId: 'student_1',
    parentId,
    classId,
    loggedByRole,
    minutesRead: 15,
    targetMinutes: 20,
    status: 'completed',
    bookTitles: ['Reading'],
  });
}

test('proxy: a co-teacher (teacherIds) CAN log for a student in their class despite empty user.classIds', async () => {
  await seedSchoolForTeacherProxy();
  const db = authDb('teacher_array');
  await assertSucceeds(proxyLog(db, { logId: 'p1', parentId: 'teacher_array', classId: 'class_1' }));
});

test('proxy: the owning teacher (teacherId) CAN log for a student in their class', async () => {
  await seedSchoolForTeacherProxy();
  const db = authDb('teacher_owner');
  await assertSucceeds(proxyLog(db, { logId: 'p2', parentId: 'teacher_owner', classId: 'class_1' }));
});

test('proxy: a teacher CANNOT log for a class they do not teach', async () => {
  await seedSchoolForTeacherProxy();
  const db = authDb('teacher_other');
  await assertFails(proxyLog(db, { logId: 'p3', parentId: 'teacher_other', classId: 'class_1' }));
});

test('proxy: parentId must be the teacher\'s own uid', async () => {
  await seedSchoolForTeacherProxy();
  const db = authDb('teacher_array');
  await assertFails(proxyLog(db, { logId: 'p4', parentId: 'someone_else', classId: 'class_1' }));
});

test('proxy: a teacher cannot write a parent-shaped log (loggedByRole != teacher)', async () => {
  await seedSchoolForTeacherProxy();
  const db = authDb('teacher_array');
  await assertFails(proxyLog(db, { logId: 'p5', parentId: 'teacher_array', classId: 'class_1', loggedByRole: 'parent' }));
});

// ── Parent↔teacher messaging gate (settings.messaging.enabled) ──────────
// Server-side backstop: a school that has turned messaging off can't have new
// comment threads created by any client. Default-on (absent setting) is already
// covered by the comment tests above — seedSchoolForComments writes no setting.

const teacherCommentDoc = {
  authorId: 'teacher_1',
  authorRole: 'teacher',
  authorName: 'Ms Smith',
  body: 'Great progress',
  studentId: 'student_1',
  parentId: 'parent_1',
  createdAt: new Date(),
};

test('comments: blocked for both roles when school messaging is disabled', async () => {
  await seedSchoolForComments();
  await seedData((db) => db.collection('schools').doc('school_1')
    .set({ settings: { messaging: { enabled: false } } }, { merge: true }));
  await assertFails(commentRef(authDb('parent_1'), 'p_off').set(parentComment));
  await assertFails(commentRef(authDb('teacher_1'), 't_off').set(teacherCommentDoc));
});

test('comments: allowed for both roles when school messaging is explicitly enabled', async () => {
  await seedSchoolForComments();
  await seedData((db) => db.collection('schools').doc('school_1')
    .set({ settings: { messaging: { enabled: true } } }, { merge: true }));
  await assertSucceeds(commentRef(authDb('parent_1'), 'p_on').set(parentComment));
  await assertSucceeds(commentRef(authDb('teacher_1'), 't_on').set(teacherCommentDoc));
});
