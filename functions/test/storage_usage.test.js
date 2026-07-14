const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const { classifyObject } = require('../lib/storage_usage.js');

test('comprehension audio maps to its school', () => {
  assert.deepEqual(
    classifyObject('schools/abc123/comprehension_audio/log456.m4a'),
    { category: 'comprehensionAudio', schoolId: 'abc123' },
  );
});

test('flutter community-book covers', () => {
  assert.deepEqual(
    classifyObject('community_books/covers/9780141036144.jpg'),
    { category: 'communityBookCovers' },
  );
});

test('portal book covers', () => {
  assert.deepEqual(
    classifyObject('bookCovers/abc123/uuid-1.webp'),
    { category: 'bookCovers' },
  );
});

test('school logos match only the direct logo.<ext> object', () => {
  assert.deepEqual(
    classifyObject('schools/abc123/logo.png'),
    { category: 'schoolLogos' },
  );
  // A nested path under schools/ that is not audio or a logo is "other".
  assert.deepEqual(
    classifyObject('schools/abc123/logo/extra.png'),
    { category: 'other' },
  );
});

test('unknown prefixes land in other, never dropped', () => {
  assert.deepEqual(classifyObject('exports/dump.csv'), { category: 'other' });
  assert.deepEqual(classifyObject('schools/abc123/misc.bin'), {
    category: 'other',
  });
});
