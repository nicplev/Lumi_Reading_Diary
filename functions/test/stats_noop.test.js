const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const { isStatsNoopUpdate } = require('../lib/stats_aggregation.js');

// Minimal structural fakes for functions.Change<DocumentSnapshot>.
const ts = (ms) => ({ toMillis: () => ms });
const snap = (data) => ({ exists: data !== null, data: () => data ?? undefined });
const change = (before, after) => ({ before: snap(before), after: snap(after) });

const countedLog = (overrides = {}) => ({
  status: 'completed',
  studentId: 's1',
  date: ts(1000),
  minutesRead: 20,
  bookTitles: ['The Hobbit'],
  ...overrides,
});

test('create (no before) is never a no-op', () => {
  assert.equal(isStatsNoopUpdate(change(null, countedLog())), false);
});

test('delete (no after) is never a no-op — powers widget-undo', () => {
  assert.equal(isStatsNoopUpdate(change(countedLog(), null)), false);
});

test('teacher-comment mirror write is a no-op', () => {
  const before = countedLog();
  const after = countedLog({ teacherComment: 'Great job!', commentedBy: 't1' });
  assert.equal(isStatsNoopUpdate(change(before, after)), true);
});

test('validation-metadata-only update is a no-op', () => {
  const before = countedLog();
  const after = countedLog({ validatedAt: ts(2000) });
  assert.equal(isStatsNoopUpdate(change(before, after)), true);
});

test('valid → invalid flip must be processed (un-counts the log)', () => {
  const before = countedLog();
  const after = countedLog({ validationStatus: 'invalid' });
  assert.equal(isStatsNoopUpdate(change(before, after)), false);
});

test('invalid → invalid metadata change is a no-op (neither side counted)', () => {
  const before = countedLog({ validationStatus: 'invalid' });
  const after = countedLog({ validationStatus: 'invalid', teacherComment: 'hm' });
  assert.equal(isStatsNoopUpdate(change(before, after)), true);
});

test('minutes edit must be processed', () => {
  assert.equal(
    isStatsNoopUpdate(change(countedLog(), countedLog({ minutesRead: 45 }))),
    false,
  );
});

test('date change must be processed', () => {
  assert.equal(
    isStatsNoopUpdate(change(countedLog(), countedLog({ date: ts(9999) }))),
    false,
  );
});

test('studentId change must be processed', () => {
  assert.equal(
    isStatsNoopUpdate(change(countedLog(), countedLog({ studentId: 's2' }))),
    false,
  );
});

test('counted → uncounted status change must be processed', () => {
  assert.equal(
    isStatsNoopUpdate(change(countedLog(), countedLog({ status: 'draft' }))),
    false,
  );
});

test('book count change must be processed', () => {
  const after = countedLog({ bookTitles: ['The Hobbit', 'Matilda'] });
  assert.equal(isStatsNoopUpdate(change(countedLog(), after)), false);
});

test('book retitle at same count is a no-op (stats only use the count)', () => {
  const after = countedLog({ bookTitles: ['Matilda'] });
  assert.equal(isStatsNoopUpdate(change(countedLog(), after)), true);
});

test('date added to a previously undated log must be processed', () => {
  const before = countedLog({ date: undefined });
  assert.equal(isStatsNoopUpdate(change(before, countedLog())), false);
});
