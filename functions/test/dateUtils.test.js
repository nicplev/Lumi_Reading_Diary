const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  localDateString,
  shiftDays,
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
} = require('../lib/dateUtils.js');

// ─── localDateString — timezone bucketing (the core off-by-one fix) ───────────

test('localDateString buckets a late-night UTC instant into the local day', () => {
  // 12:30 UTC is 00:30 the NEXT day in Auckland (UTC+12 in June) ...
  const instant = new Date('2026-06-07T12:30:00Z');
  assert.equal(localDateString(instant, 'Pacific/Auckland'), '2026-06-08');
  // ... and the PREVIOUS evening in Los Angeles (UTC-7 in June).
  assert.equal(localDateString(new Date('2026-06-07T03:30:00Z'), 'America/Los_Angeles'), '2026-06-06');
  // UTC sees it as the 7th — proving the tz actually matters.
  assert.equal(localDateString(instant, 'UTC'), '2026-06-07');
});

test('localDateString falls back to the UTC date for an invalid timezone', () => {
  assert.equal(localDateString(new Date('2026-06-07T12:30:00Z'), 'Not/AZone'), '2026-06-07');
});

// ─── shiftDays — calendar arithmetic across boundaries ────────────────────────

test('shiftDays handles day, month and year boundaries', () => {
  assert.equal(shiftDays('2026-06-07', -1), '2026-06-06');
  assert.equal(shiftDays('2026-06-07', 1), '2026-06-08');
  assert.equal(shiftDays('2026-01-01', -1), '2025-12-31');
  assert.equal(shiftDays('2026-03-01', -1), '2026-02-28'); // 2026 is not a leap year
  assert.equal(shiftDays('2024-03-01', -1), '2024-02-29'); // 2024 is a leap year
  assert.equal(shiftDays('2026-06-07', -29), '2026-05-09');
});

// ─── computeGentleStreak — the forgiving, monotonic-friendly streak ───────────

const TODAY = '2026-06-07';
const ago = (n) => shiftDays(TODAY, -n); // n local days ago

test('empty history has no streak and full rest days', () => {
  assert.deepEqual(computeGentleStreak(new Set(), TODAY), { currentStreak: 0, restDaysRemaining: 2 });
});

test('reading today only is a streak of 1', () => {
  assert.deepEqual(computeGentleStreak(new Set([ago(0)]), TODAY), { currentStreak: 1, restDaysRemaining: 2 });
});

test('consecutive nights count fully with no rest days spent', () => {
  const reads = new Set([ago(0), ago(1), ago(2)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 3, restDaysRemaining: 2 });
});

test('a single missed night is bridged (streak survives, one rest day spent)', () => {
  // read today, yesterday, and 3 days ago — the day-2-ago gap is tolerated.
  const reads = new Set([ago(0), ago(1), ago(3)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 3, restDaysRemaining: 1 });
});

test('two separate missed nights are both bridged (no rest days left)', () => {
  const reads = new Set([ago(0), ago(2), ago(4)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 3, restDaysRemaining: 0 });
});

test('three missed nights in a row end the streak (gaps behind it do not count)', () => {
  // today is read, but the cluster sits 4-5 days back behind a 3-day gap.
  const reads = new Set([ago(0), ago(4), ago(5)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 1, restDaysRemaining: 2 });
});

test('streak is not live if the last read was more than a day ago', () => {
  const reads = new Set([ago(2), ago(3)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 0, restDaysRemaining: 2 });
});

test('reading yesterday (not yet today) keeps the streak live without burning a rest day', () => {
  const reads = new Set([ago(1), ago(2), ago(3)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 3, restDaysRemaining: 2 });
});

// ─── computeLongestStreak — monotonic, same tolerance, can exceed current ─────

test('longest streak is 0 for empty history', () => {
  assert.equal(computeLongestStreak(new Set()), 0);
});

test('longest streak matches a simple consecutive run', () => {
  assert.equal(computeLongestStreak(new Set([ago(0), ago(1), ago(2)])), 3);
});

test('longest streak can exceed the current streak (a longer past run)', () => {
  // Four consecutive nights long ago, only one read recently.
  const reads = new Set([ago(0), ago(10), ago(11), ago(12), ago(13)]);
  assert.equal(computeGentleStreak(reads, TODAY).currentStreak, 1);
  assert.equal(computeLongestStreak(reads), 4);
});

// ─── countInWindow — rolling rhythm counts that slide, never reset ────────────

test('countInWindow counts distinct reads in the inclusive trailing window', () => {
  // ago(29) sits exactly on the 30-day window start (inclusive); ago(30) is out.
  const reads = new Set([ago(0), ago(29), ago(30)]);
  assert.equal(countInWindow(reads, TODAY, 30), 2);
  // The 50-day window includes ago(49) but not ago(50).
  const reads2 = new Set([ago(0), ago(49), ago(50)]);
  assert.equal(countInWindow(reads2, TODAY, 50), 2);
});
