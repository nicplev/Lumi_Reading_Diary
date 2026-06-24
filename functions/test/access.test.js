const { test } = require('node:test');
const assert = require('node:assert/strict');

// Pure access-model math (no Firebase). Built to lib/ by `npm run build`.
const {
  academicYearForDate,
  hardExpiryFor,
  nextYearLevel,
  buildStudentAccess,
  isActiveSubscriptionStatus,
} = require('../lib/access.js');

const TZ = 'Australia/Sydney';

test('academicYearForDate: mid-year date belongs to that calendar year', () => {
  assert.equal(academicYearForDate(new Date('2026-03-15T00:00:00Z'), TZ), 2026);
  assert.equal(academicYearForDate(new Date('2026-09-01T00:00:00Z'), TZ), 2026);
});

test('academicYearForDate: early-January (pre-rollover) belongs to prior year', () => {
  // 10 Jan 2026 AEDT is before the 25 Jan rollover -> still the 2025 cohort.
  assert.equal(academicYearForDate(new Date('2026-01-10T02:00:00Z'), TZ), 2025);
});

test('academicYearForDate: on/after rollover day belongs to the new year', () => {
  // 26 Jan 2026 -> 2026 cohort in session.
  assert.equal(academicYearForDate(new Date('2026-01-26T02:00:00Z'), TZ), 2026);
});

test('hardExpiryFor: end of January of the following year', () => {
  const exp = hardExpiryFor(2026, TZ);
  // Expires at the end of 31 Jan 2027 local time.
  assert.equal(exp.getUTCFullYear(), 2027);
  assert.equal(exp.getUTCMonth(), 0); // January
  // A March-2026 instant is before expiry; a March-2027 instant is after.
  assert.ok(new Date('2026-03-01T00:00:00Z') < exp);
  assert.ok(new Date('2027-03-01T00:00:00Z') > exp);
});

test('nextYearLevel: advances along the ladder', () => {
  assert.deepEqual(nextYearLevel('Prep'), { next: '1', graduated: false, changed: true });
  assert.deepEqual(nextYearLevel('1'), { next: '2', graduated: false, changed: true });
  assert.deepEqual(nextYearLevel('5'), { next: '6', graduated: false, changed: true });
});

test('nextYearLevel: entry synonyms normalise to Prep then advance', () => {
  assert.equal(nextYearLevel('Foundation').next, '1');
  assert.equal(nextYearLevel('Kindergarten').next, '1');
  assert.equal(nextYearLevel('K').next, '1');
});

test('nextYearLevel: final year graduates (no further bump)', () => {
  const r = nextYearLevel('6');
  assert.equal(r.graduated, true);
  assert.equal(r.changed, false);
});

test('nextYearLevel: unknown / empty values are left untouched', () => {
  assert.deepEqual(nextYearLevel(null), { next: null, graduated: false, changed: false });
  assert.deepEqual(nextYearLevel(''), { next: '', graduated: false, changed: false });
  assert.deepEqual(nextYearLevel('Reception'), { next: 'Reception', graduated: false, changed: false });
});

test('buildStudentAccess: active with derived expiry', () => {
  const access = buildStudentAccess({ academicYear: 2026, source: 'school_renewal', grantedBy: 'u1', tz: TZ });
  assert.equal(access.status, 'active');
  assert.equal(access.academicYear, 2026);
  assert.equal(access.source, 'school_renewal');
  assert.equal(access.grantedBy, 'u1');
  assert.deepEqual(access.expiresAt, hardExpiryFor(2026, TZ));
});

test('isActiveSubscriptionStatus: paid/comp/trial/grace are active; unpaid/cancelled are not', () => {
  for (const s of ['paid', 'comp', 'trial', 'grace']) {
    assert.equal(isActiveSubscriptionStatus(s), true, s);
  }
  for (const s of ['unpaid', 'cancelled', '', null, undefined, 'bogus']) {
    assert.equal(isActiveSubscriptionStatus(s), false, String(s));
  }
});
