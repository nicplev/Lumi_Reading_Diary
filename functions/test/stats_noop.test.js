const { test } = require('node:test');
const assert = require('node:assert/strict');

// Built to lib/ by `npm run build`.
const {
  classAggregationStudentBatches,
  isStatsNoopUpdate,
} = require('../lib/stats_aggregation.js');

test('class aggregation batches remain under Firestore disjunction limit', () => {
  const ids = Array.from({length: 34}, (_, index) => `student_${index}`);
  const batches = classAggregationStudentBatches(ids);

  assert.deepEqual(batches.map((batch) => batch.length), [15, 15, 4]);
  for (const batch of batches) {
    // The query also has `status in [completed, partial]`, so Firestore
    // normalizes it to batch.length * 2 disjunctions (maximum 30).
    assert.ok(batch.length * 2 <= 30);
  }
});

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

// ─── occurredOn (parent-logging redesign) ─────────────────────────────────────

test('occurredOn change must be processed (moves the day bucket)', () => {
  const before = countedLog({ occurredOn: '2026-07-24' });
  const after = countedLog({ occurredOn: '2026-07-23' });
  assert.equal(isStatsNoopUpdate(change(before, after)), false);
});

test('identical occurredOn stays a no-op for stats-irrelevant edits', () => {
  const before = countedLog({ occurredOn: '2026-07-24' });
  const after = countedLog({ occurredOn: '2026-07-24', teacherComment: 'Nice' });
  assert.equal(isStatsNoopUpdate(change(before, after)), true);
});

// ─── extractCountedFields — occurredOn wins the day bucket ────────────────────

const { extractCountedFields } = require('../lib/stats_aggregation.js');

// extractCountedFields calls date.toDate(); give the fake a real instant.
// 21:00 UTC on the 23rd = 07:00 AEST on the 24th.
const instantTs = {
  toDate: () => new Date('2026-07-23T21:00:00Z'),
  toMillis: () => new Date('2026-07-23T21:00:00Z').getTime(),
};

test('extractCountedFields buckets by occurredOn when present', () => {
  const fields = extractCountedFields({
    status: 'completed',
    date: instantTs,
    occurredOn: '2026-07-23', // guardian backdated to yesterday
    minutesRead: 30,
    bookTitles: ['Zog', 'Dog Man'],
  }, 'Australia/Sydney');
  assert.equal(fields.localDate, '2026-07-23');
  assert.equal(fields.minutes, 30);
  assert.equal(fields.books, 2);
});

test('extractCountedFields derives the school-local day for legacy logs', () => {
  const fields = extractCountedFields({
    status: 'completed',
    date: instantTs,
    minutesRead: 15,
    bookTitles: [],
  }, 'Australia/Sydney');
  assert.equal(fields.localDate, '2026-07-24'); // derived in school tz
  assert.equal(fields.books, 0); // unresolved-title sessions add no books
});

test('extractCountedFields ignores a malformed occurredOn', () => {
  const fields = extractCountedFields({
    status: 'completed',
    date: instantTs,
    occurredOn: 'yesterday',
    minutesRead: 15,
    bookTitles: ['Zog'],
  }, 'Australia/Sydney');
  assert.equal(fields.localDate, '2026-07-24');
});
