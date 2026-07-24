// Rules tests for the parent-logging redesign (docs/PARENT_LOGGING_FLOW_PLAN.md):
// the canonical home quick-log slot (students/{id}/quickSlots/{YYYY-MM-DD}),
// the new optional reading-log fields (occurredOn / context / titleUnresolved /
// editedAt), and the access re-check on log update/delete.
//
// The slot's whole contract is atomicity: it can only be created in the same
// batch as a fresh reading log, so when two guardians race for the day's
// default home session, the loser's batch is rejected wholesale and they
// wrote NOTHING — no orphan log, no double-count.
const fs = require('node:fs');
const path = require('node:path');
const {after, before, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {serverTimestamp} = require('firebase/firestore');

const PROJECT_ID = 'demo-lumi-quick-slot';
const RULES_PATH = path.resolve(__dirname, '../../firestore.rules');
const SCHOOL_ID = 'slot_school';
const CLASS_ID = 'slot_class';
const STUDENT_ID = 'slot_student';
const GUARDIAN_A = 'slot_parent_a';
const GUARDIAN_B = 'slot_parent_b';
const TEACHER_ID = 'slot_teacher';
const SLOT_DATE = '2026-07-24';

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

beforeEach(async () => testEnv.clearFirestore());

after(async () => testEnv.cleanup());

function db(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function schoolRef(firestore) {
  return firestore.collection('schools').doc(SCHOOL_ID);
}

function logRef(firestore, logId) {
  return schoolRef(firestore).collection('readingLogs').doc(logId);
}

function slotRef(firestore, date = SLOT_DATE) {
  return schoolRef(firestore)
    .collection('students').doc(STUDENT_ID)
    .collection('quickSlots').doc(date);
}

function validLog(uid, overrides = {}) {
  return {
    schoolId: SCHOOL_ID,
    classId: CLASS_ID,
    studentId: STUDENT_ID,
    parentId: uid,
    date: new Date(),
    createdAt: serverTimestamp(),
    minutesRead: 15,
    targetMinutes: 20,
    status: 'completed',
    bookTitles: ['The Bad Guys'],
    loggedByRole: 'parent',
    occurredOn: SLOT_DATE,
    context: 'home',
    metadata: {quickLog: true},
    ...overrides,
  };
}

function slotDoc(uid, logId) {
  return {logId, byUid: uid, createdAt: serverTimestamp()};
}

// Batch = the quick-log write shape the app uses: log create + slot create.
function quickLogBatch(firestore, uid, logId, logOverrides = {}) {
  const batch = firestore.batch();
  batch.set(logRef(firestore, logId), validLog(uid, logOverrides));
  batch.set(slotRef(firestore, logOverrides.occurredOn ?? SLOT_DATE),
    slotDoc(uid, logId));
  return batch;
}

async function seedFamily({accessExpired = false} = {}) {
  const expiresAt = accessExpired ?
    new Date(Date.now() - 24 * 60 * 60 * 1000) :
    new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const seed = context.firestore();
    const school = schoolRef(seed);
    const batch = seed.batch();
    batch.set(school, {name: 'Slot school'});
    batch.set(school.collection('classes').doc(CLASS_ID), {
      name: 'Slot class',
      teacherId: TEACHER_ID,
      studentIds: [STUDENT_ID],
    });
    batch.set(school.collection('users').doc(TEACHER_ID), {
      role: 'teacher', schoolId: SCHOOL_ID, isActive: true,
    });
    for (const uid of [GUARDIAN_A, GUARDIAN_B]) {
      batch.set(school.collection('parents').doc(uid), {
        role: 'parent', schoolId: SCHOOL_ID, linkedChildren: [STUDENT_ID],
      });
    }
    batch.set(school.collection('students').doc(STUDENT_ID), {
      schoolId: SCHOOL_ID,
      classId: CLASS_ID,
      firstName: 'Lincoln',
      lastName: 'Slot',
      isActive: true,
      parentIds: [GUARDIAN_A, GUARDIAN_B],
      access: {
        status: 'active',
        academicYear: 2026,
        expiresAt,
        source: 'book_pack_assumed',
      },
    });
    await batch.commit();
  });
}

async function countDocs(collectionPath) {
  let size = 0;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const snap = await context.firestore().collection(collectionPath).get();
    size = snap.size;
  });
  return size;
}

// ── Slot contention ─────────────────────────────────────────────────

test('quickSlot: guardian quick-log batch (log + slot) succeeds', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(quickLogBatch(a, GUARDIAN_A, 'log_a1').commit());

  const slot = await assertSucceeds(slotRef(a).get());
  assert.equal(slot.data().logId, 'log_a1');
  assert.equal(slot.data().byUid, GUARDIAN_A);
});

test('quickSlot: second guardian loses the race and writes NOTHING', async () => {
  await seedFamily();
  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a1').commit());

  // Guardian B's identical default-session batch is rejected wholesale.
  await assertFails(
    quickLogBatch(db(GUARDIAN_B), GUARDIAN_B, 'log_b1').commit());

  // The loser's log doc must not exist — no orphan session, no double-count.
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const loserLog = await logRef(context.firestore(), 'log_b1').get();
    assert.equal(loserLog.exists, false);
  });
  assert.equal(await countDocs(`schools/${SCHOOL_ID}/readingLogs`), 1);
});

test('quickSlot: same guardian cannot claim the slot twice (double tap / second device)', async () => {
  await seedFamily();
  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a1').commit());
  await assertFails(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a2').commit());
  assert.equal(await countDocs(`schools/${SCHOOL_ID}/readingLogs`), 1);
});

test('quickSlot: "Add another session" (log without slot) still succeeds after the slot is taken', async () => {
  await seedFamily();
  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a1').commit());
  await assertSucceeds(
    logRef(db(GUARDIAN_B), 'log_b_extra').set(
      validLog(GUARDIAN_B, {metadata: {quickLog: false}})));
  assert.equal(await countDocs(`schools/${SCHOOL_ID}/readingLogs`), 2);
});

test('quickSlot: cannot squat the slot by referencing an already-existing log', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  // Log created earlier, on its own (no slot).
  await assertSucceeds(logRef(a, 'log_old').set(validLog(GUARDIAN_A)));
  // Later slot create referencing it must fail: the referenced log's
  // createdAt is not request.time of THIS write.
  await assertFails(slotRef(a).set(slotDoc(GUARDIAN_A, 'log_old')));
});

test('quickSlot: slot alone (no same-batch log) cannot be created', async () => {
  await seedFamily();
  await assertFails(
    slotRef(db(GUARDIAN_A)).set(slotDoc(GUARDIAN_A, 'log_never_written')));
});

test('quickSlot: slot date must match the log occurredOn', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  const batch = a.batch();
  batch.set(logRef(a, 'log_mismatch'),
    validLog(GUARDIAN_A, {occurredOn: '2026-07-23'}));
  batch.set(slotRef(a, SLOT_DATE), slotDoc(GUARDIAN_A, 'log_mismatch'));
  await assertFails(batch.commit());
});

test('quickSlot: classroom-context log cannot claim the home slot', async () => {
  await seedFamily();
  const t = db(TEACHER_ID);
  const batch = t.batch();
  batch.set(logRef(t, 'log_classroom'), validLog(TEACHER_ID, {
    loggedByRole: 'teacher',
    context: 'classroom',
    metadata: {quickLog: false},
  }));
  batch.set(slotRef(t), slotDoc(TEACHER_ID, 'log_classroom'));
  await assertFails(batch.commit());
});

test('quickSlot: teacher home-proxy log CAN claim the slot', async () => {
  await seedFamily();
  const t = db(TEACHER_ID);
  const batch = t.batch();
  batch.set(logRef(t, 'log_proxy_home'), validLog(TEACHER_ID, {
    loggedByRole: 'teacher',
    context: 'home',
    metadata: {quickLog: false},
  }));
  batch.set(slotRef(t), slotDoc(TEACHER_ID, 'log_proxy_home'));
  await assertSucceeds(batch.commit());
});

test('quickSlot: undo (batch delete log + slot) frees the slot for the co-guardian', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(quickLogBatch(a, GUARDIAN_A, 'log_a1').commit());

  const undo = a.batch();
  undo.delete(logRef(a, 'log_a1'));
  undo.delete(slotRef(a));
  await assertSucceeds(undo.commit());

  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_B), GUARDIAN_B, 'log_b1').commit());
});

test('quickSlot: a co-guardian cannot delete or overwrite the other guardian\'s slot', async () => {
  await seedFamily();
  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a1').commit());
  const b = db(GUARDIAN_B);
  await assertFails(slotRef(b).delete());
  await assertFails(slotRef(b).update({byUid: GUARDIAN_B}));
});

test('quickSlot: linked guardian can read the slot; an unlinked parent cannot', async () => {
  await seedFamily();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await schoolRef(context.firestore())
      .collection('parents').doc('outsider').set({
        role: 'parent', schoolId: SCHOOL_ID, linkedChildren: ['someone_else'],
      });
  });
  await assertSucceeds(
    quickLogBatch(db(GUARDIAN_A), GUARDIAN_A, 'log_a1').commit());
  await assertSucceeds(slotRef(db(GUARDIAN_B)).get());
  await assertFails(slotRef(db('outsider')).get());
});

// ── New optional log fields ─────────────────────────────────────────

test('readingLogs: create with occurredOn/context/titleUnresolved shape is accepted', async () => {
  await seedFamily();
  await assertSucceeds(logRef(db(GUARDIAN_A), 'log_fields').set(
    validLog(GUARDIAN_A, {
      bookTitles: [],
      titleUnresolved: true,
      metadata: {quickLog: false},
    })));
});

test('readingLogs: malformed occurredOn is rejected', async () => {
  await seedFamily();
  await assertFails(logRef(db(GUARDIAN_A), 'log_bad_date').set(
    validLog(GUARDIAN_A, {occurredOn: '24/07/2026'})));
});

test('readingLogs: titleUnresolved with a non-empty bookTitles is rejected (no placeholder rides along)', async () => {
  await seedFamily();
  await assertFails(logRef(db(GUARDIAN_A), 'log_bad_unresolved').set(
    validLog(GUARDIAN_A, {titleUnresolved: true})));
});

test('readingLogs: a parent cannot write context=classroom', async () => {
  await seedFamily();
  await assertFails(logRef(db(GUARDIAN_A), 'log_bad_ctx').set(
    validLog(GUARDIAN_A, {context: 'classroom'})));
});

test('readingLogs: occurredOn is immutable after create', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(logRef(a, 'log_a1').set(validLog(GUARDIAN_A)));
  await assertFails(
    logRef(a, 'log_a1').update({occurredOn: '2026-07-20'}));
});

test('readingLogs: editedAt must be request.time when touched', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(logRef(a, 'log_a1').set(validLog(GUARDIAN_A)));
  await assertSucceeds(logRef(a, 'log_a1').update({
    minutesRead: 25,
    editedAt: serverTimestamp(),
  }));
  await assertFails(logRef(a, 'log_a1').update({
    minutesRead: 30,
    editedAt: new Date('2020-01-01T00:00:00Z'),
  }));
});

// ── Access re-check on mutation ─────────────────────────────────────

test('readingLogs: lapsed access blocks the owner\'s update and delete (fail-closed)', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(logRef(a, 'log_a1').set(validLog(GUARDIAN_A)));

  // Access lapses after the log exists (renewal missed / school off-boarded).
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await schoolRef(context.firestore())
      .collection('students').doc(STUDENT_ID).update({
        'access.expiresAt': new Date(Date.now() - 60_000),
      });
  });

  await assertFails(logRef(a, 'log_a1').update({minutesRead: 45}));
  await assertFails(logRef(a, 'log_a1').delete());
});

test('readingLogs: live access still permits the owner\'s update and delete', async () => {
  await seedFamily();
  const a = db(GUARDIAN_A);
  await assertSucceeds(logRef(a, 'log_a1').set(validLog(GUARDIAN_A)));
  await assertSucceeds(logRef(a, 'log_a1').update({minutesRead: 45}));
  await assertSucceeds(logRef(a, 'log_a1').delete());
});
