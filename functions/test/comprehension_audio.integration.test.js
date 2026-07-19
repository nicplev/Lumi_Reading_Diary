const { before, after, beforeEach, test } = require('node:test');
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { File } = require('@google-cloud/storage');
const fs = require('node:fs');
const path = require('node:path');

const PROJECT_ID = 'demo-lumi-audio';
const BUCKET = `${PROJECT_ID}.appspot.com`;

let audio;

before(() => {
  if (admin.apps.length === 0) {
    admin.initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET });
  }
  audio = require('../lib/comprehension_retention');
});

after(async () => {
  await Promise.all(admin.apps.map((app) => app.delete()));
});

beforeEach(async () => {
  const db = admin.firestore();
  for (const name of [
    'adminAuditLog',
    'backendRateLimits',
    'opsCronHeartbeats',
    'platformConfig',
    'schools',
  ]) {
    await db.recursiveDelete(db.collection(name));
  }
  await admin.storage().bucket().deleteFiles({ force: true });
});

function auth(uid, token = {}) {
  return { uid, token: { sub: uid, ...token } };
}

function invoke(fn, uid, data, token = {}) {
  return fn.run({
    data,
    auth: uid ? auth(uid, token) : undefined,
    app: undefined,
    instanceIdToken: undefined,
    rawRequest: {},
  });
}

async function rejectsCode(promise, code) {
  await assert.rejects(promise, (error) => error?.code === code);
}

function validM4aHeader() {
  const bytes = Buffer.alloc(32);
  bytes.writeUInt32BE(32, 0);
  bytes.write('ftyp', 4, 'ascii');
  bytes.write('M4A ', 8, 'ascii');
  return bytes;
}

async function seedFlag(enabled = true) {
  await admin.firestore().doc('platformConfig/comprehensionRecording').set({
    enabled,
    updatedAt: admin.firestore.Timestamp.now(),
  });
}

async function seedLog({
  schoolId = 'school_x',
  logId = 'log_x',
  classId = 'class_x',
  parentId = 'parent_x',
  uploaded = false,
  storedPath,
  createdAt = admin.firestore.Timestamp.now(),
  retentionDays = 30,
} = {}) {
  await admin.firestore().doc(`schools/${schoolId}`).set({
    settings: {
      comprehensionRecording: {
        enabled: true,
        authorityVersion: 'school-audio-v1-2026-07-17',
        authorityConfirmedAt: admin.firestore.Timestamp.now(),
        retentionDays,
      },
    },
  }, { merge: true });
  const path = storedPath ??
    `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
  const ref = admin.firestore().doc(
    `schools/${schoolId}/readingLogs/${logId}`
  );
  await ref.set({
    schoolId,
    logId,
    classId,
    studentId: `student_${schoolId}`,
    parentId,
    loggedByRole: 'parent',
    createdAt,
    comprehensionAudioUploaded: uploaded,
    ...(uploaded ? {
      comprehensionAudioPath: path,
      comprehensionAudioDurationSec: 12,
      comprehensionAudioValidationVersion: 'ffmpeg-aac-mono-v1',
      comprehensionAudioObjectGeneration: 'test-generation',
    } : {}),
  });
  return ref;
}

async function seedTeacher({
  uid,
  schoolId = 'school_x',
  role = 'teacher',
  classId = 'class_x',
  assigned = true,
}) {
  const db = admin.firestore();
  await db.doc(`schools/${schoolId}/users/${uid}`).set({
    uid,
    schoolId,
    role,
    isActive: true,
  });
  if (role === 'teacher' && assigned) {
    await db.doc(`schools/${schoolId}/classes/${classId}`).set({
      schoolId,
      teacherIds: admin.firestore.FieldValue.arrayUnion(uid),
    }, { merge: true });
  }
}

async function saveAudio({
  schoolId = 'school_x',
  logId = 'log_x',
  ownerUid = 'parent_x',
  bytes = validM4aHeader(),
  contentType = 'audio/mp4',
  metadata = {},
  pending = false,
} = {}) {
  const path = pending ?
    `comprehension_audio_uploads/${schoolId}/${logId}.m4a` :
    `schools/${schoolId}/comprehension_audio/${logId}.m4a`;
  const file = admin.storage().bucket().file(path);
  await file.save(bytes, {
    metadata: {
      contentType,
      metadata: {
        ownerUid,
        schoolId,
        logId,
        studentId: `student_${schoolId}`,
        ...metadata,
      },
    },
  });
  return file;
}

test('upload confirmation decodes pending media and writes a canonical server object', async () => {
  await seedFlag(true);
  const log = await seedLog();
  const pending = await saveAudio({
    pending: true,
    bytes: fs.readFileSync(path.join(__dirname, 'fixtures', 'valid-tone.m4a')),
  });

  const result = await invoke(
    audio.confirmComprehensionAudioUpload,
    'parent_x',
    { schoolId: 'school_x', logId: 'log_x', durationSec: 12 }
  );

  assert.equal(result.confirmed, true);
  assert.equal(result.validationVersion, 'ffmpeg-aac-mono-v1');
  const data = (await log.get()).data();
  assert.equal(
    data.comprehensionAudioPath,
    'schools/school_x/comprehension_audio/log_x.m4a'
  );
  assert.equal(data.comprehensionAudioDurationSec, 1);
  assert.equal(data.comprehensionAudioUploaded, true);
  assert.equal(data.comprehensionAudioValidationVersion, 'ffmpeg-aac-mono-v1');
  assert.match(data.comprehensionAudioSha256, /^[a-f0-9]{64}$/);
  assert.ok(data.comprehensionAudioUploadedAt);
  assert.equal((await pending.exists())[0], false);
  assert.equal((await admin.storage().bucket().file(
    'schools/school_x/comprehension_audio/log_x.m4a'
  ).exists())[0], true);

  const retry = await invoke(
    audio.confirmComprehensionAudioUpload,
    'parent_x',
    { schoolId: 'school_x', logId: 'log_x', durationSec: 12 }
  );
  assert.deepEqual(retry, { confirmed: true, alreadyConfirmed: true });
});

test('upload confirmation fails closed for unauthenticated, disabled and non-owner requests', async () => {
  await seedLog();
  await saveAudio({ pending: true });
  const input = { schoolId: 'school_x', logId: 'log_x', durationSec: 12 };

  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, null, input),
    'unauthenticated'
  );
  await seedFlag(false);
  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, 'parent_x', input),
    'failed-precondition'
  );
  await seedFlag(true);
  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, 'parent_outsider', input),
    'permission-denied'
  );
});

test('upload confirmation fails closed without current school authority evidence', async () => {
  await seedFlag(true);
  await seedLog();
  await admin.firestore().doc('schools/school_x').update({
    'settings.comprehensionRecording': {
      enabled: true,
      authorityVersion: 'outdated-authority-version',
      authorityConfirmedAt: admin.firestore.Timestamp.now(),
      retentionDays: 30,
    },
  });

  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, 'parent_x', {
      schoolId: 'school_x', logId: 'log_x', durationSec: 12,
    }),
    'failed-precondition'
  );
});

test('upload confirmation deletes MIME-only junk and mismatched metadata', async () => {
  await seedFlag(true);
  await seedLog();
  const junk = await saveAudio({
    pending: true,
    bytes: validM4aHeader(),
  });
  const input = { schoolId: 'school_x', logId: 'log_x', durationSec: 12 };

  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, 'parent_x', input),
    'failed-precondition'
  );
  assert.equal((await junk.exists())[0], false);

  const mismatch = await saveAudio({
    pending: true,
    metadata: { logId: 'other_log' },
  });
  await rejectsCode(
    invoke(audio.confirmComprehensionAudioUpload, 'parent_x', input),
    'failed-precondition'
  );
  assert.equal((await mismatch.exists())[0], false);
});

test('playback callable enforces class/school scope, kill switch and canonical path', async () => {
  await seedFlag(true);
  await seedLog({
    uploaded: true,
    storedPath: 'schools/school_y/comprehension_audio/injected.m4a',
  });
  await seedTeacher({ uid: 'teacher_assigned' });
  await seedTeacher({ uid: 'teacher_unassigned', assigned: false });
  await seedTeacher({ uid: 'teacher_y', schoolId: 'school_y', classId: 'class_y' });

  let signedPath;
  const originalGetSignedUrl = File.prototype.getSignedUrl;
  File.prototype.getSignedUrl = async function getSignedUrl(options) {
    signedPath = this.name;
    assert.equal(options.action, 'read');
    assert.ok(options.expires > Date.now());
    return [`https://local.invalid/${encodeURIComponent(this.name)}`];
  };
  try {
    const result = await invoke(
      audio.getComprehensionAudioUrl,
      'teacher_assigned',
      { schoolId: 'school_x', logId: 'log_x' }
    );
    assert.equal(
      signedPath,
      'schools/school_x/comprehension_audio/log_x.m4a'
    );
    assert.equal(result.expiresInSec, 900);
    assert.match(result.url, /^https:\/\/local\.invalid\//);

    await rejectsCode(
      invoke(audio.getComprehensionAudioUrl, 'teacher_unassigned', {
        schoolId: 'school_x', logId: 'log_x',
      }),
      'permission-denied'
    );
    await rejectsCode(
      invoke(audio.getComprehensionAudioUrl, 'teacher_y', {
        schoolId: 'school_x', logId: 'log_x',
      }),
      'permission-denied'
    );
    await seedFlag(false);
    await rejectsCode(
      invoke(audio.getComprehensionAudioUrl, 'teacher_assigned', {
        schoolId: 'school_x', logId: 'log_x',
      }),
      'failed-precondition'
    );
    await seedFlag(true);
    await admin.firestore().doc('schools/school_x').update({
      'settings.comprehensionRecording.enabled': false,
    });
    await rejectsCode(
      invoke(audio.getComprehensionAudioUrl, 'teacher_assigned', {
        schoolId: 'school_x', logId: 'log_x',
      }),
      'failed-precondition'
    );
  } finally {
    File.prototype.getSignedUrl = originalGetSignedUrl;
  }
});

test('manual deletion follows the canonical path and never an injected stored path', async () => {
  await seedFlag(false); // deletion remains available while collection is off
  const log = await seedLog({
    uploaded: true,
    storedPath: 'schools/school_y/comprehension_audio/injected.m4a',
  });
  await seedTeacher({ uid: 'teacher_assigned' });
  const canonical = await saveAudio();
  const injected = await saveAudio({ schoolId: 'school_y', logId: 'injected' });

  const result = await invoke(audio.deleteComprehensionAudio, 'teacher_assigned', {
    schoolId: 'school_x', logId: 'log_x',
  }, { email: 'teacher@example.test' });

  assert.deepEqual(result, { deleted: true });
  assert.equal((await canonical.exists())[0], false);
  assert.equal((await injected.exists())[0], true);
  const data = (await log.get()).data();
  assert.equal(data.comprehensionAudioUploaded, false);
  assert.equal(data.comprehensionAudioPath, undefined);
  const audits = await admin.firestore().collection('adminAuditLog')
    .where('action', '==', 'comprehensionAudio.manualDelete').get();
  assert.equal(audits.size, 1);
  assert.equal(
    audits.docs[0].data().metadata.storagePath,
    'schools/school_x/comprehension_audio/log_x.m4a'
  );
});

test('manual deletion denies unassigned and cross-school teachers', async () => {
  await seedLog({ uploaded: true });
  await seedTeacher({ uid: 'teacher_unassigned', assigned: false });
  await seedTeacher({ uid: 'teacher_y', schoolId: 'school_y', classId: 'class_y' });

  await rejectsCode(
    invoke(audio.deleteComprehensionAudio, 'teacher_unassigned', {
      schoolId: 'school_x', logId: 'log_x',
    }),
    'permission-denied'
  );
  await rejectsCode(
    invoke(audio.deleteComprehensionAudio, 'teacher_y', {
      schoolId: 'school_x', logId: 'log_x',
    }),
    'permission-denied'
  );
});

test('scheduled retention deletes canonical objects and quarantines injected paths', async () => {
  const old = admin.firestore.Timestamp.fromMillis(
    Date.now() - 30 * 24 * 60 * 60 * 1000
  );
  await admin.firestore().doc('platformConfig/comprehensionRetention').set({
    enabled: false,
    retentionDays: 30,
  });
  const canonicalLog = await seedLog({
    logId: 'expired_good', uploaded: true, createdAt: old, retentionDays: 7,
  });
  const rejectedLog = await seedLog({
    logId: 'expired_injected',
    uploaded: true,
    createdAt: old,
    storedPath: 'schools/school_y/comprehension_audio/do_not_delete.m4a',
    retentionDays: 7,
  });
  const retainedLog = await seedLog({
    schoolId: 'school_long_retention',
    logId: 'not_expired_for_school',
    uploaded: true,
    createdAt: old,
    retentionDays: 90,
  });
  const canonical = await saveAudio({ logId: 'expired_good' });
  const injected = await saveAudio({
    schoolId: 'school_y', logId: 'do_not_delete',
  });
  const retained = await saveAudio({
    schoolId: 'school_long_retention',
    logId: 'not_expired_for_school',
  });

  await audio.cleanupComprehensionAudio.run({});

  assert.equal((await canonical.exists())[0], false);
  assert.equal((await injected.exists())[0], true);
  assert.equal((await retained.exists())[0], true);
  const good = (await canonicalLog.get()).data();
  const rejected = (await rejectedLog.get()).data();
  const notExpired = (await retainedLog.get()).data();
  assert.equal(good.comprehensionAudioUploaded, false);
  assert.ok(good.comprehensionAudioDeletedAt);
  assert.equal(rejected.comprehensionAudioUploaded, false);
  assert.ok(rejected.comprehensionAudioPathRejectedAt);
  assert.equal(notExpired.comprehensionAudioUploaded, true);
  const config = (await admin.firestore()
    .doc('platformConfig/comprehensionRetention').get()).data();
  assert.equal(config.lastRunStats.deletedCount, 1);
  assert.equal(config.lastRunStats.failedCount, 1);
  assert.deepEqual(config.lastRunStats.retentionPolicyCounts, {7: 1, 90: 1});
  assert.equal(config.lastRunStats.legacySevenDaySchoolCount, 1);
  assert.equal(config.lastRunStats.trigger, 'cron');
});
