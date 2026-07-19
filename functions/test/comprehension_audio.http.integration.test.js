const { before, after, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const fs = require('node:fs');
const path = require('node:path');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-lumi-audio-http';
const BUCKET = `${PROJECT_ID}.appspot.com`;
const FUNCTIONS_ORIGIN = `http://127.0.0.1:5001/${PROJECT_ID}/australia-southeast1`;
const AUTH_ORIGIN = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099'}`;

const identities = {};

function validM4aHeader() {
  const bytes = Buffer.alloc(32);
  bytes.writeUInt32BE(32, 0);
  bytes.write('ftyp', 4, 'ascii');
  bytes.write('M4A ', 8, 'ascii');
  return bytes;
}

async function createIdentity(label) {
  const response = await fetch(
    `${AUTH_ORIGIN}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        email: `${label}@lumi.local`,
        password: 'Local-test-only-Password1!',
        returnSecureToken: true,
      }),
    }
  );
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return {uid: body.localId, token: body.idToken};
}

async function callFunction(name, data, token) {
  const headers = {'content-type': 'application/json'};
  if (token) headers.authorization = `Bearer ${token}`;
  const response = await fetch(`${FUNCTIONS_ORIGIN}/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({data}),
  });
  return {status: response.status, body: await response.json()};
}

async function seedFlag(enabled = true) {
  await admin.firestore().doc('platformConfig/comprehensionRecording').set({
    enabled,
    updatedAt: admin.firestore.Timestamp.now(),
  });
}

// The confirm callable now also requires the per-school audio authority
// (PR #420); mirror the shape used by comprehension_audio.integration.test.js.
async function seedSchoolAuthority(schoolId) {
  await admin.firestore().doc(`schools/${schoolId}`).set({
    settings: {
      comprehensionRecording: {
        enabled: true,
        authorityVersion: 'school-audio-v1-2026-07-17',
        authorityConfirmedAt: admin.firestore.Timestamp.now(),
        retentionDays: 30,
      },
    },
  }, {merge: true});
}

async function seedLog({schoolId, logId, classId, parentId, uploaded = false}) {
  const canonicalPath = `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
  const ref = admin.firestore().doc(`schools/${schoolId}/readingLogs/${logId}`);
  await ref.set({
    schoolId,
    logId,
    classId,
    studentId: `student_${logId}`,
    parentId,
    loggedByRole: 'parent',
    createdAt: admin.firestore.Timestamp.now(),
    comprehensionAudioUploaded: uploaded,
    ...(uploaded ? {
      // Deliberately hostile stored value: privileged operations must ignore it.
      comprehensionAudioPath: 'schools/school_y/comprehension_audio/injected.m4a',
      comprehensionAudioDurationSec: 12,
      comprehensionAudioValidationVersion: 'ffmpeg-aac-mono-v1',
      comprehensionAudioObjectGeneration: 'test-generation',
    } : {}),
  });
  return {ref, canonicalPath};
}

async function seedTeacher({identity, schoolId, classId, assigned}) {
  const db = admin.firestore();
  await db.doc(`schools/${schoolId}/users/${identity.uid}`).set({
    uid: identity.uid,
    schoolId,
    role: 'teacher',
    isActive: true,
  });
  await db.doc(`schools/${schoolId}/classes/${classId}`).set({
    schoolId,
    teacherIds: assigned ? [identity.uid] : [],
  });
}

async function saveAudio({schoolId, logId, ownerUid}) {
  const path = `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
  const file = admin.storage().bucket().file(path);
  await file.save(validM4aHeader(), {
    metadata: {
      contentType: 'audio/mp4',
      metadata: {ownerUid, schoolId, logId, studentId: `student_${logId}`},
    },
  });
  return file;
}

async function savePendingAudio({schoolId, logId, ownerUid}) {
  const objectPath = `comprehension_audio_uploads/${schoolId}/${logId}.m4a`;
  const file = admin.storage().bucket().file(objectPath);
  await file.save(
    fs.readFileSync(path.join(__dirname, 'fixtures', 'valid-tone.m4a')),
    {
      metadata: {
        contentType: 'audio/mp4',
        metadata: {ownerUid, schoolId, logId, studentId: `student_${logId}`},
      },
    }
  );
  return file;
}

before(async () => {
  admin.initializeApp({projectId: PROJECT_ID, storageBucket: BUCKET});
  identities.parent = await createIdentity('audio-parent');
  identities.teacherX = await createIdentity('audio-teacher-x');
  identities.teacherY = await createIdentity('audio-teacher-y');
});

after(async () => {
  await Promise.all(admin.apps.map((app) => app.delete()));
});

test('actual callable HTTP boundary rejects an unauthenticated request', async () => {
  const result = await callFunction(
    'getComprehensionAudioUrl',
    {schoolId: 'school_http', logId: 'log_unauth'}
  );
  assert.equal(result.status, 401);
  assert.equal(result.body.error.status, 'UNAUTHENTICATED');
});

test('authenticated owner confirms a canonical upload through HTTP', async () => {
  const schoolId = 'school_http_confirm';
  const logId = 'log_http_confirm';
  await seedFlag(true);
  await seedSchoolAuthority(schoolId);
  const {ref, canonicalPath} = await seedLog({
    schoolId,
    logId,
    classId: 'class_confirm',
    parentId: identities.parent.uid,
  });
  const pending = await savePendingAudio({
    schoolId,
    logId,
    ownerUid: identities.parent.uid,
  });

  const result = await callFunction(
    'confirmComprehensionAudioUpload',
    {schoolId, logId, durationSec: 12},
    identities.parent.token
  );

  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.result.confirmed, true);
  assert.equal(
    result.body.result.validationVersion,
    'ffmpeg-aac-mono-v1'
  );
  const data = (await ref.get()).data();
  assert.equal(data.comprehensionAudioPath, canonicalPath);
  assert.equal(data.comprehensionAudioUploaded, true);
  assert.equal(data.comprehensionAudioDurationSec, 1);
  assert.equal((await pending.exists())[0], false);
});

test('School Y teacher cannot access a School X recording through HTTP', async () => {
  const schoolId = 'school_http_x';
  const logId = 'log_http_cross_school';
  await seedFlag(true);
  await seedLog({
    schoolId,
    logId,
    classId: 'class_x',
    parentId: identities.parent.uid,
    uploaded: true,
  });
  await seedTeacher({
    identity: identities.teacherY,
    schoolId: 'school_http_y',
    classId: 'class_y',
    assigned: true,
  });

  const result = await callFunction(
    'getComprehensionAudioUrl',
    {schoolId, logId},
    identities.teacherY.token
  );
  assert.equal(result.status, 403, JSON.stringify(result.body));
  assert.equal(result.body.error.status, 'PERMISSION_DENIED');
});

test('assigned School X teacher deletes only the canonical object through HTTP', async () => {
  const schoolId = 'school_http_delete';
  const logId = 'log_http_delete';
  const classId = 'class_delete';
  const {ref, canonicalPath} = await seedLog({
    schoolId,
    logId,
    classId,
    parentId: identities.parent.uid,
    uploaded: true,
  });
  await seedTeacher({
    identity: identities.teacherX,
    schoolId,
    classId,
    assigned: true,
  });
  const canonical = await saveAudio({
    schoolId,
    logId,
    ownerUid: identities.parent.uid,
  });
  const injected = admin.storage().bucket().file(
    'schools/school_y/comprehension_audio/injected.m4a'
  );
  await injected.save(validM4aHeader(), {metadata: {contentType: 'audio/mp4'}});

  const result = await callFunction(
    'deleteComprehensionAudio',
    {schoolId, logId},
    identities.teacherX.token
  );

  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.deepEqual(result.body.result, {deleted: true});
  assert.equal((await canonical.exists())[0], false);
  assert.equal((await injected.exists())[0], true);
  const data = (await ref.get()).data();
  assert.equal(data.comprehensionAudioUploaded, false);
  assert.equal(data.comprehensionAudioPath, undefined);
  assert.equal(canonicalPath.endsWith(`${logId}.m4a`), true);
});
