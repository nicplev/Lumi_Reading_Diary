const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  localDateString,
  localDateUtcRange,
  shiftDays,
  computeGentleStreak,
  computeLongestStreak,
  countInWindow,
  parseTermDates,
  buildIsCountingDay,
  isValidOccurredOn,
  resolveOccurrenceDate,
  MAX_REST_DAYS,
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

test('localDateUtcRange maps a Melbourne local day to UTC', () => {
  const range = localDateUtcRange('2026-06-07', 'Australia/Melbourne');
  assert.equal(range.startInclusive.toISOString(), '2026-06-06T14:00:00.000Z');
  assert.equal(range.endExclusive.toISOString(), '2026-06-07T14:00:00.000Z');
});

test('localDateUtcRange maps a Sydney summer day to UTC', () => {
  const range = localDateUtcRange('2026-01-15', 'Australia/Sydney');
  assert.equal(range.startInclusive.toISOString(), '2026-01-14T13:00:00.000Z');
  assert.equal(range.endExclusive.toISOString(), '2026-01-15T13:00:00.000Z');
});

test('localDateUtcRange follows Melbourne DST start and end', () => {
  const spring = localDateUtcRange('2026-10-04', 'Australia/Melbourne');
  assert.equal(spring.startInclusive.toISOString(), '2026-10-03T14:00:00.000Z');
  assert.equal(spring.endExclusive.toISOString(), '2026-10-04T13:00:00.000Z');
  assert.equal(
    spring.endExclusive.getTime() - spring.startInclusive.getTime(),
    23 * 60 * 60 * 1000,
  );

  const autumn = localDateUtcRange('2026-04-05', 'Australia/Melbourne');
  assert.equal(autumn.startInclusive.toISOString(), '2026-04-04T13:00:00.000Z');
  assert.equal(autumn.endExclusive.toISOString(), '2026-04-05T14:00:00.000Z');
  assert.equal(
    autumn.endExclusive.getTime() - autumn.startInclusive.getTime(),
    25 * 60 * 60 * 1000,
  );
});

test('localDateUtcRange falls back to UTC for an invalid timezone', () => {
  const range = localDateUtcRange('2026-06-07', 'Not/AZone');
  assert.equal(range.startInclusive.toISOString(), '2026-06-07T00:00:00.000Z');
  assert.equal(range.endExclusive.toISOString(), '2026-06-08T00:00:00.000Z');
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

test('streak stays live while still bridgeable (last read up to 3 days back)', () => {
  // A Friday reader must not see 0 on Sunday: reading tonight would still
  // bridge the gap, so the streak keeps displaying.
  const reads = new Set([ago(2), ago(3)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 2, restDaysRemaining: 2 });
  // Last read exactly maxRestDays+1 back — the last day it is still live.
  const fri = new Set([ago(3), ago(4)]);
  assert.deepEqual(computeGentleStreak(fri, TODAY), { currentStreak: 2, restDaysRemaining: 2 });
});

test('streak goes to 0 once the gap is no longer bridgeable', () => {
  // 4 counting days since the last read: even reading tonight could not
  // bridge the 3 misses in between, so the streak is dead.
  const reads = new Set([ago(4), ago(5)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 0, restDaysRemaining: 2 });
});

test('reading yesterday (not yet today) keeps the streak live without burning a rest day', () => {
  const reads = new Set([ago(1), ago(2), ago(3)]);
  assert.deepEqual(computeGentleStreak(reads, TODAY), { currentStreak: 3, restDaysRemaining: 2 });
});

// ─── term dates — holiday-aware streaks ───────────────────────────────────────

test('parseTermDates drops malformed entries and keeps valid ranges', () => {
  assert.deepEqual(parseTermDates(undefined), []);
  assert.deepEqual(parseTermDates('nope'), []);
  assert.deepEqual(parseTermDates([
    { start: '2026-04-20', end: '2026-06-26' },        // valid
    { start: '2026-07-13', end: '2026-09-18', label: 'Term 3' }, // valid, extra key ok
    { start: '2026-06-26', end: '2026-04-20' },        // start > end → dropped
    { start: '20-04-2026', end: '2026-06-26' },        // bad format → dropped
    { start: '2026-04-20' },                            // missing end → dropped
    null,                                               // → dropped
  ]), [
    { start: '2026-04-20', end: '2026-06-26' },
    { start: '2026-07-13', end: '2026-09-18' },
  ]);
});

test('parseTermDates reads the portal settings map shape (termNStart/termNEnd Timestamps)', () => {
  // The portal stores date-only picks as UTC-midnight values; mimic Firestore
  // Timestamps with toDate().
  const ts = (iso) => ({ toDate: () => new Date(`${iso}T00:00:00Z`) });
  const parsed = parseTermDates({
    term2Start: ts('2026-04-20'), term2End: ts('2026-06-26'),
    term1Start: ts('2026-01-28'), term1End: ts('2026-04-02'),
    term3Start: ts('2026-07-13'),                     // missing End → dropped
    term4Start: ts('2026-10-06'), term4End: 'garbage', // bad End → dropped
  });
  // Sorted by start date, incomplete/bad terms dropped.
  assert.deepEqual(parsed, [
    { start: '2026-01-28', end: '2026-04-02' },
    { start: '2026-04-20', end: '2026-06-26' },
  ]);
  // ISO strings and JS Dates are accepted too.
  assert.deepEqual(parseTermDates({
    term1Start: '2026-01-28T00:00:00', term1End: new Date('2026-04-02T00:00:00Z'),
  }), [{ start: '2026-01-28', end: '2026-04-02' }]);
  // Empty map → no terms (every day counts).
  assert.deepEqual(parseTermDates({}), []);
});

test('buildIsCountingDay: empty terms → every day counts; ranges are inclusive', () => {
  const always = buildIsCountingDay([]);
  assert.equal(always('2026-01-01'), true);
  const inTerm = buildIsCountingDay([{ start: '2026-04-20', end: '2026-06-26' }]);
  assert.equal(inTerm('2026-04-20'), true);  // first day inclusive
  assert.equal(inTerm('2026-06-26'), true);  // last day inclusive
  assert.equal(inTerm('2026-04-19'), false); // day before
  assert.equal(inTerm('2026-06-27'), false); // day after
});

// Term ends Fri 2026-06-05; holidays until term 2 starts Mon 2026-06-22.
const TERMS = buildIsCountingDay(parseTermDates([
  { start: '2026-05-01', end: '2026-06-05' },
  { start: '2026-06-22', end: '2026-08-28' },
]));

test('a streak survives (and displays) right through a term break', () => {
  // Read the last 3 days of term, then nothing — mid-holidays the streak
  // still shows because zero counting days have elapsed.
  const reads = new Set(['2026-06-03', '2026-06-04', '2026-06-05']);
  const midBreak = computeGentleStreak(reads, '2026-06-14', MAX_REST_DAYS, TERMS);
  assert.deepEqual(midBreak, { currentStreak: 3, restDaysRemaining: 2 });
  // First day back is a leading-edge unread day — still live, still 3.
  const firstDayBack = computeGentleStreak(reads, '2026-06-22', MAX_REST_DAYS, TERMS);
  assert.deepEqual(firstDayBack, { currentStreak: 3, restDaysRemaining: 2 });
});

test('reading across a break joins into one streak without spending rest days', () => {
  // End of term 1 + first two nights of term 2: the 16 holiday days between
  // are free, so this is one continuous streak of 4.
  const reads = new Set([
    '2026-06-04', '2026-06-05', '2026-06-22', '2026-06-23',
  ]);
  const result = computeGentleStreak(reads, '2026-06-23', MAX_REST_DAYS, TERMS);
  assert.deepEqual(result, { currentStreak: 4, restDaysRemaining: 2 });
});

test('reading ON holiday days still extends the streak', () => {
  const reads = new Set(['2026-06-05', '2026-06-10', '2026-06-12']);
  const result = computeGentleStreak(reads, '2026-06-12', MAX_REST_DAYS, TERMS);
  assert.deepEqual(result, { currentStreak: 3, restDaysRemaining: 2 });
});

test('in-term misses still spend rest days as before, holidays or not', () => {
  // Back in term 2: read Mon 22nd, skip Tue-Thu (3 counting misses) → dead.
  const reads = new Set(['2026-06-22']);
  const result = computeGentleStreak(reads, '2026-06-26', MAX_REST_DAYS, TERMS);
  assert.deepEqual(result, { currentStreak: 0, restDaysRemaining: 2 });
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

// ─── resolveOccurrenceDate — client-stated day wins, derived day is fallback ──

test('isValidOccurredOn accepts YYYY-MM-DD only', () => {
  assert.equal(isValidOccurredOn('2026-07-24'), true);
  assert.equal(isValidOccurredOn('24/07/2026'), false);
  assert.equal(isValidOccurredOn('2026-7-24'), false);
  assert.equal(isValidOccurredOn(''), false);
  assert.equal(isValidOccurredOn(null), false);
  assert.equal(isValidOccurredOn(20260724), false);
});

test('resolveOccurrenceDate prefers a valid occurredOn (Yesterday backdating)', () => {
  // Logged at 07:00 Sydney on the 24th, explicitly for yesterday's reading.
  const instant = new Date('2026-07-23T21:00:00Z'); // 07:00 AEST on the 24th
  assert.equal(
    resolveOccurrenceDate('2026-07-23', instant, 'Australia/Sydney'),
    '2026-07-23',
  );
});

test('resolveOccurrenceDate falls back to the school-local derived day for legacy logs', () => {
  // 23:30 Sydney on the 24th is 13:30 UTC on the 24th.
  const instant = new Date('2026-07-24T13:30:00Z');
  assert.equal(
    resolveOccurrenceDate(undefined, instant, 'Australia/Sydney'),
    '2026-07-24',
  );
  // Malformed values are ignored, not trusted.
  assert.equal(
    resolveOccurrenceDate('not-a-date', instant, 'Australia/Sydney'),
    '2026-07-24',
  );
});
