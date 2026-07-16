const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');

const PROJECT_ID = 'demo-lumi-deletion';
const BUCKET = `${PROJECT_ID}.appspot.com`;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
  }
});

after(async () => {
  await Promise.all(admin.apps.map((app) => app.delete()));
});

beforeEach(async () => {
  await admin.firestore().recursiveDelete(admin.firestore().collection('schools'));
  for (const name of [
    'deletionJobs',
    'feedback',
    'notifications',
    'studentLinkCodes',
    'userSchoolIndex',
    'users',
  ]) {
    await admin.firestore().recursiveDelete(admin.firestore().collection(name));
  }
});

test('account cascade removes identity while preserving deidentified school reading history', async () => {
  const { deleteAccountData } = require('../lib/deletion');
  const db = admin.firestore();
  const uid = 'parent_delete';
  const school = db.collection('schools').doc('school_account');
  await admin.auth().createUser({ uid, email: 'delete@example.test' });
  await school.set({ parentCount: 1, teacherCount: 0, studentCount: 1 });
  await school.collection('parents').doc(uid).set({
    role: 'parent',
    schoolId: school.id,
    linkedChildren: ['student_1'],
  });
  await school.collection('students').doc('student_1').set({
    firstName: 'Ari',
    lastName: 'Reader',
    schoolId: school.id,
    parentIds: [uid],
    guardianProfiles: { [uid]: { fullName: 'Delete Me' } },
  });
  const log = school.collection('readingLogs').doc('log_1');
  await log.set({
    schoolId: school.id,
    studentId: 'student_1',
    parentId: uid,
    loggedByName: 'Delete Me',
    loggedByLabel: 'Guardian',
    loggedByRole: 'parent',
    notes: 'private note',
    parentComment: 'private comment',
    comprehensionAudioPath: `schools/${school.id}/comprehension_audio/log_1.m4a`,
    comprehensionAudioUploaded: true,
  });
  await log.collection('comments').doc('mine').set({
    authorId: uid,
    authorRole: 'parent',
    body: 'remove me',
    createdAt: admin.firestore.Timestamp.now(),
  });
  await log.collection('comments').doc('teacher').set({
    authorId: 'teacher_1',
    authorRole: 'teacher',
    authorName: 'Teacher',
    body: 'retain school feedback',
    createdAt: admin.firestore.Timestamp.now(),
  });
  await db.collection('feedback').doc('feedback_1').set({ userId: uid });
  await db.collection('userSchoolIndex').doc('index_1').set({ userId: uid });
  await db.collection('users').doc(uid).set({ email: 'delete@example.test' });
  const audio = admin.storage().bucket().file(
    `schools/${school.id}/comprehension_audio/log_1.m4a`
  );
  await audio.save(Buffer.from('voice'));
  const pendingAudio = admin.storage().bucket().file(
    `comprehension_audio_uploads/${school.id}/log_1.m4a`
  );
  await pendingAudio.save(Buffer.from('untrusted voice'));

  await deleteAccountData(uid);

  await assert.rejects(
    admin.auth().getUser(uid),
    (error) => error?.code === 'auth/user-not-found'
  );
  assert.equal((await school.collection('parents').doc(uid).get()).exists, false);
  const student = (await school.collection('students').doc('student_1').get()).data();
  assert.deepEqual(student.parentIds, []);
  assert.equal(student.guardianProfiles?.[uid], undefined);
  const retainedLog = (await log.get()).data();
  assert.equal(retainedLog.parentId, 'deleted_account');
  assert.equal(retainedLog.loggedByName, 'Former guardian');
  assert.equal(retainedLog.notes, undefined);
  assert.equal(retainedLog.comprehensionAudioPath, undefined);
  assert.equal((await log.collection('comments').doc('mine').get()).exists, false);
  assert.equal((await log.collection('comments').doc('teacher').get()).exists, true);
  assert.equal((await audio.exists())[0], false);
  assert.equal((await pendingAudio.exists())[0], false);
  assert.equal((await db.collection('feedback').doc('feedback_1').get()).exists, false);
  assert.equal((await db.collection('userSchoolIndex').doc('index_1').get()).exists, false);
  assert.equal((await db.collection('users').doc(uid).get()).exists, false);
  assert.equal((await school.get()).data().parentCount, 0);
});

test('student cascade removes the profile, history, audio and every linked roster reference', async () => {
  const { deleteStudentData } = require('../lib/deletion');
  const db = admin.firestore();
  const school = db.collection('schools').doc('school_student');
  const studentId = 'student_delete';
  await school.set({ parentCount: 1, teacherCount: 1, studentCount: 1 });
  const student = school.collection('students').doc(studentId);
  await student.set({
    firstName: 'Ari',
    lastName: 'Reader',
    schoolId: school.id,
    classId: 'class_1',
    parentIds: ['parent_1'],
    isActive: true,
  });
  await student.collection('readingLevelEvents').doc('event_1').set({ level: 'Blue' });
  await school.collection('parents').doc('parent_1').set({ linkedChildren: [studentId] });
  await school.collection('classes').doc('class_1').set({ studentIds: [studentId] });
  await school.collection('readingGroups').doc('group_1').set({
    studentIds: [studentId],
    studentOverrides: { [studentId]: { target: 10 } },
  });
  await school.collection('allocations').doc('allocation_1').set({
    studentIds: [],
    studentOverrides: { [studentId]: { target: 10 } },
  });
  await school.collection('notificationCampaigns').doc('campaign_1').set({
    targetStudentIds: [studentId],
  });
  await school.collection('parents').doc('parent_1')
    .collection('notifications').doc('notification_1').set({ studentIds: [studentId] });
  await db.collection('studentLinkCodes').doc('code_1').set({ studentId });
  const log = school.collection('readingLogs').doc('log_student');
  await log.set({ schoolId: school.id, studentId, parentId: 'parent_1' });
  await log.collection('comments').doc('comment_1').set({ body: 'nested' });
  const audio = admin.storage().bucket().file(
    `schools/${school.id}/comprehension_audio/log_student.m4a`
  );
  await audio.save(Buffer.from('voice'));
  const pendingAudio = admin.storage().bucket().file(
    `comprehension_audio_uploads/${school.id}/log_student.m4a`
  );
  await pendingAudio.save(Buffer.from('untrusted voice'));

  await deleteStudentData(school.id, studentId);

  assert.equal((await student.get()).exists, false);
  assert.equal((await log.get()).exists, false);
  assert.equal((await audio.exists())[0], false);
  assert.equal((await pendingAudio.exists())[0], false);
  assert.deepEqual((await school.collection('parents').doc('parent_1').get()).data().linkedChildren, []);
  assert.deepEqual((await school.collection('classes').doc('class_1').get()).data().studentIds, []);
  const group = (await school.collection('readingGroups').doc('group_1').get()).data();
  assert.deepEqual(group.studentIds, []);
  assert.equal(group.studentOverrides?.[studentId], undefined);
  const allocation = (await school.collection('allocations').doc('allocation_1').get()).data();
  assert.equal(allocation.studentOverrides?.[studentId], undefined);
  assert.deepEqual((await school.collection('notificationCampaigns').doc('campaign_1').get()).data().targetStudentIds, []);
  assert.equal((await school.collection('parents').doc('parent_1')
    .collection('notifications').doc('notification_1').get()).exists, false);
  assert.equal((await db.collection('studentLinkCodes').doc('code_1').get()).exists, false);
  assert.equal((await school.get()).data().studentCount, 0);
});
