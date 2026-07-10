const { test } = require('node:test');
const assert = require('node:assert/strict');

const { normalizeUnlinkReason } = require('../lib/parent_linking.js');

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
