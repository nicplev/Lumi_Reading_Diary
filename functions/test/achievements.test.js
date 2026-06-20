const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  DEFAULT_ACHIEVEMENT_THRESHOLDS,
  computeAwardableAchievements,
} = require('../lib/achievements.js');

const T = DEFAULT_ACHIEVEMENT_THRESHOLDS;
const ids = (list) => list.map((a) => a.id).sort();

// ─── The regression that motivated this: a student who ALREADY meets a
// threshold (e.g. seed/imported data, or detector deployed late) must still be
// awarded. The old "threshold crossing" logic left them at 0 forever. ──────────

test('awards on current state for an already-qualified student (no crossing)', () => {
  const stats = { totalReadingDays: 15, totalBooksRead: 6, totalMinutesRead: 0 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  // 15 nights -> days_t1 (10); 6 books -> books_t1 (5); 1+ night -> first_log.
  // NOT days_t2 (50), books_t2 (10), or any minutes tier (0 < 300).
  assert.deepEqual(got, ['books_t1', 'days_t1', 'first_log'].sort());
});

test('does not re-award achievements already earned (idempotent)', () => {
  const stats = { totalReadingDays: 15, totalBooksRead: 6, totalMinutesRead: 0 };
  const earned = new Set(['days_t1', 'books_t1', 'first_log']);
  const got = computeAwardableAchievements(stats, earned, T);
  assert.deepEqual(got, []);
});

test('awards every tier currently met at once (backfill case)', () => {
  const stats = { totalReadingDays: 365, totalBooksRead: 100, totalMinutesRead: 6000 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  assert.deepEqual(got, ids([
    { id: 'days_t1' }, { id: 'days_t2' }, { id: 'days_t3' }, { id: 'days_t4' },
    { id: 'books_t1' }, { id: 'books_t2' }, { id: 'books_t3' }, { id: 'books_t4' }, { id: 'books_t5' },
    { id: 'minutes_t1' }, { id: 'minutes_t2' }, { id: 'minutes_t3' }, { id: 'minutes_t4' }, { id: 'minutes_t5' },
    { id: 'first_log' },
  ]));
  assert.equal(got.length, 15); // all 14 tiers + first_log
});

test('never awards a streak badge', () => {
  const stats = { totalReadingDays: 365, totalBooksRead: 100, totalMinutesRead: 6000 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  assert.ok(!got.some((id) => id.startsWith('streak')));
});

test('zero / missing stats award nothing (not even first_log)', () => {
  assert.deepEqual(computeAwardableAchievements({}, new Set(), T), []);
  assert.deepEqual(
    computeAwardableAchievements({ totalReadingDays: 0 }, new Set(), T), []);
});

test('first_log fires at the very first night', () => {
  const got = ids(computeAwardableAchievements(
    { totalReadingDays: 1 }, new Set(), T));
  assert.deepEqual(got, ['first_log']);
});

test('non-numeric / null stat values are treated as 0', () => {
  const stats = {
    totalReadingDays: null, totalBooksRead: undefined, totalMinutesRead: 'NaN',
  };
  assert.deepEqual(computeAwardableAchievements(stats, new Set(), T), []);
});

test('respects custom (school) thresholds', () => {
  const custom = { ...T, books: [2, 4, 8, 16, 32] };
  const got = ids(computeAwardableAchievements(
    { totalBooksRead: 3, totalReadingDays: 0 }, new Set(), custom));
  // 3 books clears the custom tier-1 (2) only.
  assert.deepEqual(got, ['books_t1']);
});
