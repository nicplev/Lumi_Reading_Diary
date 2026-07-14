const { test } = require('node:test');
const assert = require('node:assert/strict');

const { computeStreakRefresh } = require('../lib/streak_refresh.js');
const { buildIsCountingDay, parseTermDates } = require('../lib/dateUtils.js');

const everyDayCounts = () => true;

// ─── computeStreakRefresh — the daily decay/slide logic ───────────────────────

test('dead streak decays to 0 once the gap is no longer bridgeable', () => {
  // Last read 4 counting days ago — reading tonight can't bridge it.
  const stats = {
    currentStreak: 5,
    restDaysRemaining: 2,
    last30DaysCount: 5,
    last50DaysCount: 5,
    readingDates: ['2026-07-06', '2026-07-07', '2026-07-08', '2026-07-09', '2026-07-10'],
  };
  const changed = computeStreakRefresh(stats, '2026-07-14', everyDayCounts);
  assert.equal(changed['stats.currentStreak'], 0);
});

test('live streak with correct stored values is a no-op (null, no write)', () => {
  const stats = {
    currentStreak: 3,
    restDaysRemaining: 2,
    last30DaysCount: 3,
    last50DaysCount: 3,
    readingDates: ['2026-07-12', '2026-07-13', '2026-07-14'],
  };
  assert.equal(computeStreakRefresh(stats, '2026-07-14', everyDayCounts), null);
});

test('holiday-frozen streak survives untouched (prod regression shape)', () => {
  // Term 1 only configured — everything after 3 Apr is "holidays", so the
  // streak must NOT decay even with 4 blank days at the leading edge.
  const isCountingDay = buildIsCountingDay(
    parseTermDates([{ start: '2026-01-29', end: '2026-04-03' }]),
  );
  const stats = {
    currentStreak: 10,
    restDaysRemaining: 2,
    last30DaysCount: 8,
    last50DaysCount: 10,
    readingDates: [
      '2026-05-26', '2026-06-03', '2026-06-15', '2026-06-16', '2026-06-19',
      '2026-06-20', '2026-06-28', '2026-07-05', '2026-07-08', '2026-07-10',
    ],
  };
  assert.equal(computeStreakRefresh(stats, '2026-07-14', isCountingDay), null);
});

test('correct VIC term dates decay the same shape to a streak of 4', () => {
  // Same reading history as above but with real 2026 VIC terms configured:
  // the 26 May / 3 Jun nights detach (in-term gaps blow the rest budget) and
  // the live chain is 28 Jun → 5 Jul → 8 Jul → 10 Jul across the break.
  const isCountingDay = buildIsCountingDay(parseTermDates([
    { start: '2026-01-28', end: '2026-04-02' },
    { start: '2026-04-20', end: '2026-06-26' },
    { start: '2026-07-13', end: '2026-09-18' },
    { start: '2026-10-05', end: '2026-12-18' },
  ]));
  const stats = {
    currentStreak: 10,
    restDaysRemaining: 2,
    last30DaysCount: 8,
    last50DaysCount: 10,
    readingDates: [
      '2026-05-26', '2026-06-03', '2026-06-15', '2026-06-16', '2026-06-19',
      '2026-06-20', '2026-06-28', '2026-07-05', '2026-07-08', '2026-07-10',
    ],
  };
  const changed = computeStreakRefresh(stats, '2026-07-14', isCountingDay);
  assert.equal(changed['stats.currentStreak'], 4);
});

test('rolling 30-night window slides even when the streak is unchanged', () => {
  // The 14 Jun read sat inside the window yesterday (last30 = 4) but falls
  // out today: last30 must drop to 3 while the streak fields stay as stored
  // (14 Jun still counts for the 50-night window).
  const stats = {
    currentStreak: 3,
    restDaysRemaining: 2,
    last30DaysCount: 4,
    last50DaysCount: 4,
    readingDates: ['2026-06-14', '2026-07-12', '2026-07-13', '2026-07-14'],
  };
  const changed = computeStreakRefresh(stats, '2026-07-14', everyDayCounts);
  assert.deepEqual(changed, { 'stats.last30DaysCount': 3 });
});

test('missing readingDates array is left for the weekly reconciler (null)', () => {
  const stats = { currentStreak: 7, restDaysRemaining: 1 };
  assert.equal(computeStreakRefresh(stats, '2026-07-14', everyDayCounts), null);
});

test('only changed fields are returned, as stats.-prefixed update paths', () => {
  const stats = {
    currentStreak: 2,
    restDaysRemaining: 1, // stale: recompute says 2 (no gaps bridged)
    last30DaysCount: 2,
    last50DaysCount: 2,
    readingDates: ['2026-07-13', '2026-07-14'],
  };
  const changed = computeStreakRefresh(stats, '2026-07-14', everyDayCounts);
  assert.deepEqual(changed, { 'stats.restDaysRemaining': 2 });
});
