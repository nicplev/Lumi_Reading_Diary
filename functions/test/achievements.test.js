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
  // 15 nights -> days_t1 (10); 1+ night -> first_log.
  // NOT days_t2 (50), any minutes tier (0 < 300), or any books tier (retired).
  assert.deepEqual(got, ['days_t1', 'first_log'].sort());
});

test('does not re-award achievements already earned (idempotent)', () => {
  const stats = { totalReadingDays: 15, totalBooksRead: 6, totalMinutesRead: 0 };
  const earned = new Set(['days_t1', 'first_log']);
  const got = computeAwardableAchievements(stats, earned, T);
  assert.deepEqual(got, []);
});

test('awards every tier currently met at once (backfill case)', () => {
  const stats = { totalReadingDays: 365, totalBooksRead: 100, totalMinutesRead: 6000 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  assert.deepEqual(got, ids([
    { id: 'days_t1' }, { id: 'days_t2' }, { id: 'days_t3' }, { id: 'days_t4' },
    { id: 'minutes_t1' }, { id: 'minutes_t2' }, { id: 'minutes_t3' }, { id: 'minutes_t4' }, { id: 'minutes_t5' },
    { id: 'first_log' },
  ]));
  assert.equal(got.length, 10); // all 9 awardable tiers + first_log
});

test('never awards a streak badge', () => {
  const stats = { totalReadingDays: 365, totalBooksRead: 100, totalMinutesRead: 6000 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  assert.ok(!got.some((id) => id.startsWith('streak')));
});

test('never awards a books badge (books-read is not honestly trackable)', () => {
  const stats = { totalReadingDays: 365, totalBooksRead: 100, totalMinutesRead: 6000 };
  const got = ids(computeAwardableAchievements(stats, new Set(), T));
  assert.ok(!got.some((id) => id.startsWith('books')));
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
  const custom = { ...T, minutes: [10, 20, 40, 80, 160] };
  const got = ids(computeAwardableAchievements(
    { totalMinutesRead: 15, totalReadingDays: 0 }, new Set(), custom));
  // 15 minutes clears the custom tier-1 (10) only.
  assert.deepEqual(got, ['minutes_t1']);
});

test('custom books thresholds are ignored — the books ladder is retired', () => {
  const custom = { ...T, books: [2, 4, 8, 16, 32] };
  const got = computeAwardableAchievements(
    { totalBooksRead: 100, totalReadingDays: 0 }, new Set(), custom);
  assert.deepEqual(got, []);
});
