'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  nextPublicCodeCounter,
} = require('../lib/public_code_rate_limit.js');
const {
  assertSchoolCodeUsable,
} = require('../lib/code_verification.js');

const ts = (millis) => ({toMillis: () => millis});

test('public code counter starts trusted hour/day windows and increments', () => {
  const next = nextPublicCodeCounter({}, 1_000_000);
  assert.deepEqual(next, {
    hourStartMs: 1_000_000,
    hourCount: 1,
    dayStartMs: 1_000_000,
    dayCount: 1,
  });
});

test('public code counter rejects the hourly boundary', () => {
  assert.throws(
    () => nextPublicCodeCounter({
      hourStart: ts(1_000_000),
      hourCount: 30,
      dayStart: ts(1_000_000),
      dayCount: 30,
    }, 1_000_001),
    (error) => error.code === 'resource-exhausted',
  );
});

test('public code counter resets expired windows without trusting old counts', () => {
  const now = 100_000_000;
  const next = nextPublicCodeCounter({
    hourStart: ts(0),
    hourCount: 999,
    dayStart: ts(0),
    dayCount: 999,
  }, now);
  assert.equal(next.hourStartMs, now);
  assert.equal(next.hourCount, 1);
  assert.equal(next.dayStartMs, now);
  assert.equal(next.dayCount, 1);
});

test('school join code validity fails closed on expiry and max usage', () => {
  assert.doesNotThrow(() => assertSchoolCodeUsable({
    isActive: true,
    expiresAt: new Date('2030-02-01T00:00:00Z'),
    usageCount: 1,
    maxUsages: 2,
  }, new Date('2030-01-01T00:00:00Z')));

  assert.throws(
    () => assertSchoolCodeUsable({
      isActive: true,
      expiresAt: new Date('2029-12-31T00:00:00Z'),
    }, new Date('2030-01-01T00:00:00Z')),
    (error) => error.details?.kind === 'code_expired',
  );
  assert.throws(
    () => assertSchoolCodeUsable({
      isActive: true,
      usageCount: 2,
      maxUsages: 2,
    }, new Date('2030-01-01T00:00:00Z')),
    (error) => error.details?.kind === 'code_max_usage',
  );
});
