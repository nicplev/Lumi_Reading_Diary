const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const { pickTopReader, previousWeek } = require('../lib/top_reader_award.js');

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
