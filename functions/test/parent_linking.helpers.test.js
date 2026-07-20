const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  normalizeUnlinkReason,
  teacherAssignedToClass,
} = require('../lib/parent_linking.js');

test('normalizeUnlinkReason trims an optional audit note', () => {
  assert.equal(normalizeUnlinkReason(undefined), null);
  assert.equal(normalizeUnlinkReason('   '), null);
  assert.equal(
    normalizeUnlinkReason('  Linked to the wrong guardian  '),
    'Linked to the wrong guardian',
  );
});

test('normalizeUnlinkReason accepts 250 characters and rejects larger input', () => {
  assert.equal(normalizeUnlinkReason('a'.repeat(250)).length, 250);
  assert.throws(
    () => normalizeUnlinkReason('a'.repeat(251)),
    (error) => error?.code === 'invalid-argument',
  );
});

test('teacherAssignedToClass matches single teacherId and teacherIds array', () => {
  assert.equal(teacherAssignedToClass({ teacherId: 'u1' }, 'u1'), true);
  assert.equal(teacherAssignedToClass({ teacherIds: ['u2', 'u1'] }, 'u1'), true);
  assert.equal(
    teacherAssignedToClass({ teacherId: 'x', teacherIds: ['u1'] }, 'u1'),
    true,
  );
});

test('teacherAssignedToClass denies an unassigned teacher and bad input', () => {
  assert.equal(teacherAssignedToClass({ teacherId: 'other' }, 'u1'), false);
  assert.equal(teacherAssignedToClass({ teacherIds: ['a', 'b'] }, 'u1'), false);
  assert.equal(teacherAssignedToClass({}, 'u1'), false);
  assert.equal(teacherAssignedToClass(null, 'u1'), false);
  assert.equal(teacherAssignedToClass(undefined, 'u1'), false);
  // A missing/empty class doc must never satisfy assignment.
  assert.equal(teacherAssignedToClass({ teacherIds: [] }, ''), false);
});
