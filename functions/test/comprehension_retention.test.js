const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const {
  audioPathMustBeQuarantined,
  comprehensionAudioObjectPath,
  hasIsoMediaFtypSignature,
  teacherIsAssignedToClassData,
} = require('../lib/comprehension_retention.js');

test('audio object path is derived only from school and log ids', () => {
  assert.equal(
    comprehensionAudioObjectPath('school_x', 'log_123'),
    'schools/school_x/comprehension_audio/log_123.m4a',
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
