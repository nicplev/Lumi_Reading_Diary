const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const {
  pickTopReader,
  previousWeek,
  weekContainsCountingDay,
} = require('../lib/top_reader_award.js');
const { parseTermDates, buildIsCountingDay } = require('../lib/dateUtils.js');

const totals = (obj) => new Map(Object.entries(obj).map(([id, v]) =>
  [id, typeof v === 'number' ? { minutes: v, logs: 1 } : v]));

test('pickTopReader: nobody read → null', () => {
  assert.equal(pickTopReader(new Map()), null);
  assert.equal(pickTopReader(totals({ a: 0, b: 0 })), null);
});

test('pickTopReader: most minutes wins', () => {
  assert.equal(pickTopReader(totals({ a: 30, b: 90, c: 45 })), 'b');
});

test('pickTopReader: tie on minutes → more logs wins', () => {
  const t = new Map([
    ['a', { minutes: 60, logs: 2 }],
    ['b', { minutes: 60, logs: 5 }],
  ]);
  assert.equal(pickTopReader(t), 'b');
});

test('pickTopReader: full tie → lowest studentId (deterministic)', () => {
  const t = new Map([
    ['zoe', { minutes: 60, logs: 3 }],
    ['ada', { minutes: 60, logs: 3 }],
  ]);
  assert.equal(pickTopReader(t), 'ada');
});

test('previousWeek: Monday run → prior Mon..Sun in Sydney', () => {
  // 2026-07-05T19:00Z = Mon 2026-07-06 05:00 Sydney (AEST, UTC+10).
  const w = previousWeek(new Date('2026-07-05T19:00:00Z'), 'Australia/Sydney');
  assert.equal(w.firstDay, '2026-06-29'); // Monday
  assert.equal(w.lastDay, '2026-07-05'); // Sunday
  assert.equal(w.weekOf, '2026-06-29');
});

test('previousWeek: mid-week run still returns the last complete week', () => {
  // Wed 2026-07-08 Sydney.
  const w = previousWeek(new Date('2026-07-07T22:00:00Z'), 'Australia/Sydney');
  assert.equal(w.firstDay, '2026-06-29');
  assert.equal(w.lastDay, '2026-07-05');
});

test('weekContainsCountingDay: all-holiday weeks are skipped, part-term weeks are not', () => {
  // Term 2 ends Fri 2026-06-26; term 3 starts Mon 2026-07-13.
  const isCountingDay = buildIsCountingDay(parseTermDates([
    { start: '2026-04-20', end: '2026-06-26' },
    { start: '2026-07-13', end: '2026-09-18' },
  ]));
  // Mon 29 Jun – Sun 5 Jul: entirely inside the holidays → skip.
  assert.equal(weekContainsCountingDay('2026-06-29', '2026-07-05', isCountingDay), false);
  // Mon 22 Jun – Sun 28 Jun: contains the last week of term → award.
  assert.equal(weekContainsCountingDay('2026-06-22', '2026-06-28', isCountingDay), true);
  // Mon 13 Jul: first week back → award.
  assert.equal(weekContainsCountingDay('2026-07-13', '2026-07-19', isCountingDay), true);
  // No term dates configured → every week counts.
  assert.equal(weekContainsCountingDay('2026-06-29', '2026-07-05', buildIsCountingDay([])), true);
});
