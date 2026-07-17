const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');

// Built to lib/ by `npm run build`.
const {
  assertFreshAudioAppCheckToken,
  audioPathMustBeQuarantined,
  comprehensionAudioObjectPath,
  comprehensionAudioUploadObjectPath,
  hasIsoMediaFtypSignature,
  teacherIsAssignedToClassData,
} = require('../lib/comprehension_retention.js');
const {
  AUDIO_AUTHORITY_VERSION,
  retentionDaysForSchool,
  schoolAudioCollectionIsAuthorised,
} = require('../lib/audio_authority.js');
const {
  AudioMediaValidationError,
  validateAndTranscodeAudioBuffer,
} = require('../lib/audio_media_validation.js');

test('audio callables reject replayed App Check tokens when enforced', () => {
  assert.throws(
    () => assertFreshAudioAppCheckToken(
      {app: {alreadyConsumed: true}},
      true,
    ),
    (error) => error.code === 'failed-precondition',
  );
  assert.doesNotThrow(() => assertFreshAudioAppCheckToken(
    {app: {alreadyConsumed: false}},
    true,
  ));
  assert.doesNotThrow(() => assertFreshAudioAppCheckToken(
    {app: {alreadyConsumed: true}},
    false,
  ));
});

test('audio object path is derived only from school and log ids', () => {
  assert.equal(
    comprehensionAudioObjectPath('school_x', 'log_123'),
    'schools/school_x/comprehension_audio/log_123.m4a',
  );
});

test('untrusted and canonical audio paths are separate', () => {
  assert.equal(
    comprehensionAudioUploadObjectPath('school_x', 'log_123'),
    'comprehension_audio_uploads/school_x/log_123.m4a',
  );
  assert.notEqual(
    comprehensionAudioUploadObjectPath('school_x', 'log_123'),
    comprehensionAudioObjectPath('school_x', 'log_123'),
  );
});

test('cross-school injected audio path is quarantined', () => {
  const expected = comprehensionAudioObjectPath('school_x', 'log_123');

  assert.equal(
    audioPathMustBeQuarantined(
      'schools/school_y/comprehension_audio/child_voice.m4a',
      expected,
    ),
    true,
  );
  assert.equal(audioPathMustBeQuarantined(expected, expected), false);
  assert.equal(audioPathMustBeQuarantined(undefined, expected), true);
});

test('audio receipt accepts an ISO media ftyp header and rejects MIME-only junk', () => {
  const valid = Buffer.alloc(24);
  valid.writeUInt32BE(24, 0);
  valid.write('ftyp', 4, 'ascii');
  valid.write('M4A ', 8, 'ascii');
  assert.equal(hasIsoMediaFtypSignature(valid), true);
  assert.equal(hasIsoMediaFtypSignature(Buffer.from('not really audio')), false);

  const wrongBox = Buffer.alloc(16);
  wrongBox.writeUInt32BE(16, 0);
  wrongBox.write('free', 4, 'ascii');
  assert.equal(hasIsoMediaFtypSignature(wrongBox), false);
});

test('server media validator fully decodes and canonicalises real m4a audio', async () => {
  const input = await fs.readFile(
    path.join(__dirname, 'fixtures', 'valid-tone.m4a'),
  );
  const result = await validateAndTranscodeAudioBuffer(input);

  assert.ok(result.durationMs >= 1100 && result.durationMs <= 1300);
  assert.equal(result.sizeBytes, result.bytes.length);
  assert.match(result.sha256, /^[a-f0-9]{64}$/);
  assert.equal(result.bytes.toString('ascii', 4, 8), 'ftyp');
});

test('server media validator rejects truncated ftyp-only bytes', async () => {
  const fake = Buffer.alloc(32);
  fake.writeUInt32BE(32, 0);
  fake.write('ftyp', 4, 'ascii');
  fake.write('M4A ', 8, 'ascii');
  await assert.rejects(
    validateAndTranscodeAudioBuffer(fake),
    (error) => error instanceof AudioMediaValidationError,
  );
});

test('server media validator rejects audio beyond the 60 second bound', async () => {
  const input = await fs.readFile(
    path.join(__dirname, 'fixtures', 'too-long.m4a'),
  );
  await assert.rejects(
    validateAndTranscodeAudioBuffer(input),
    (error) => error instanceof AudioMediaValidationError,
  );
});

test('audio access recognises only the assigned teacher or co-teacher', () => {
  const classData = {
    teacherId: 'teacher_a',
    teacherIds: ['teacher_b'],
  };

  assert.equal(teacherIsAssignedToClassData('teacher_a', classData), true);
  assert.equal(teacherIsAssignedToClassData('teacher_b', classData), true);
  assert.equal(teacherIsAssignedToClassData('teacher_c', classData), false);
  assert.equal(teacherIsAssignedToClassData('teacher_a', {}), false);
});

test('school audio collection requires current server-recorded authority', () => {
  const valid = {
    settings: {
      comprehensionRecording: {
        enabled: true,
        authorityVersion: AUDIO_AUTHORITY_VERSION,
        authorityConfirmedAt: new Date(),
        retentionDays: 30,
      },
    },
  };
  assert.equal(schoolAudioCollectionIsAuthorised(valid), true);
  assert.equal(schoolAudioCollectionIsAuthorised({
    ...valid,
    settings: {comprehensionRecording: {
      ...valid.settings.comprehensionRecording,
      authorityVersion: 'old',
    }},
  }), false);
  assert.equal(schoolAudioCollectionIsAuthorised({
    settings: {comprehensionRecording: {enabled: true}},
  }), false);
});

test('school retention uses an allowed school choice or the legacy default', () => {
  assert.equal(retentionDaysForSchool({
    settings: {comprehensionRecording: {retentionDays: 7}},
  }, 90), 7);
  assert.equal(retentionDaysForSchool({
    settings: {comprehensionRecording: {retentionDays: 14}},
  }, 90), 90);
});
