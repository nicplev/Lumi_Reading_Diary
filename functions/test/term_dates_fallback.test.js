const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  detectSchoolState,
  planTermDatesFill,
  mergeStateTermTables,
} = require('../lib/term_dates_fallback.js');
const { AU_STATE_TERM_DATES } = require('../lib/state_term_dates_data.js');

const VIC_2026 = AU_STATE_TERM_DATES['2026'].VIC;

// UTC-midnight Date for a slot the school entered itself (the portal's
// storage convention — coerceTermDateStr reads the UTC date back out).
const d = (s) => new Date(`${s}T00:00:00Z`);

// ─── detectSchoolState ────────────────────────────────────────────────────────

test('abbreviation in the address wins', () => {
  assert.equal(
    detectSchoolState({ address: '123 School Street, Beaumaris VIC 3193' }),
    'VIC',
  );
});

test('explicit state field beats the address', () => {
  assert.equal(
    detectSchoolState({ state: 'qld', address: '1 Street, Sydney NSW 2000' }),
    'QLD',
  );
});

test('abbreviations only match as uppercase words (no "Sale"/"Nt" hits)', () => {
  // No uppercase token, no state name, no postcode → falls through to null.
  assert.equal(detectSchoolState({ address: '2 Sale Road, Ntaria' }), null);
});

test('spelt-out state name is recognised', () => {
  assert.equal(
    detectSchoolState({ address: '5 High St, Launceston, Tasmania' }),
    'TAS',
  );
});

test('postcode fallback uses the LAST 4-digit token', () => {
  // "2600" street number (ACT range) must not shadow the WA postcode.
  assert.equal(detectSchoolState({ address: '2600 Albany Hwy, 6111' }), 'WA');
  assert.equal(detectSchoolState({ address: '10 Northbourne Ave, 2601' }), 'ACT');
});

test('no address, no state → null', () => {
  assert.equal(detectSchoolState({}), null);
});

// ─── planTermDatesFill ────────────────────────────────────────────────────────

test('term-1-only school gets terms 2-4 filled, custom term 1 kept', () => {
  // The prod shape that froze streaks: only Term 1 entered (slightly
  // different from the official dates — a custom entry that must survive).
  const plan = planTermDatesFill(
    { term1Start: d('2026-01-29'), term1End: d('2026-04-03') },
    VIC_2026,
    2026,
  );
  assert.deepEqual(plan.filledTerms, [2, 3, 4]);
  assert.equal(plan.fields['termDates.term1Start'], undefined);
  assert.deepEqual(
    plan.fields['termDates.term2Start'], d('2026-04-20'));
  assert.deepEqual(
    plan.fields['termDates.term4End'], d('2026-12-18'));
});

test('fully entered current-year dates → null (nothing to fill)', () => {
  const plan = planTermDatesFill(
    {
      // Customised by a day or two from the official VIC dates.
      term1Start: d('2026-01-29'), term1End: d('2026-04-03'),
      term2Start: d('2026-04-21'), term2End: d('2026-06-25'),
      term3Start: d('2026-07-14'), term3End: d('2026-09-17'),
      term4Start: d('2026-10-06'), term4End: d('2026-12-17'),
    },
    VIC_2026,
    2026,
  );
  assert.equal(plan, null);
});

test("last year's dates are stale → all four terms rolled forward", () => {
  const plan = planTermDatesFill(
    {
      term1Start: d('2025-01-28'), term1End: d('2025-04-04'),
      term2Start: d('2025-04-22'), term2End: d('2025-07-04'),
      term3Start: d('2025-07-21'), term3End: d('2025-09-19'),
      term4Start: d('2025-10-06'), term4End: d('2025-12-19'),
    },
    VIC_2026,
    2026,
  );
  assert.deepEqual(plan.filledTerms, [1, 2, 3, 4]);
});

test('future-year custom entry (typed in December) is respected', () => {
  const plan = planTermDatesFill(
    { term1Start: d('2027-02-01'), term1End: d('2027-03-30') },
    VIC_2026,
    2026,
  );
  // Term 1 kept (future year), terms 2-4 filled for the current year.
  assert.deepEqual(plan.filledTerms, [2, 3, 4]);
});

test('half-entered slot (start without end) is treated as missing', () => {
  const plan = planTermDatesFill(
    { term2Start: d('2026-04-20') },
    VIC_2026,
    2026,
  );
  assert.deepEqual(plan.filledTerms, [1, 2, 3, 4]);
});

test('empty/absent termDates fills everything', () => {
  const plan = planTermDatesFill(undefined, VIC_2026, 2026);
  assert.deepEqual(plan.filledTerms, [1, 2, 3, 4]);
  assert.equal(Object.keys(plan.fields).length, 8);
});

// ─── mergeStateTermTables ─────────────────────────────────────────────────────

test('override doc years win over the bundled table', () => {
  const merged = mergeStateTermTables({
    2026: { VIC: [{ term: 1, start: '2026-02-01', end: '2026-04-01' }] },
    updatedAt: { seconds: 1, nanoseconds: 0 }, // non-year keys are ignored
  });
  assert.equal(merged['2026'].VIC[0].start, '2026-02-01');
  // Untouched bundled years remain.
  assert.equal(merged['2027'].VIC[0].start, '2027-01-28');
});

test('no override doc → bundled table as-is', () => {
  const merged = mergeStateTermTables(undefined);
  assert.deepEqual(merged, AU_STATE_TERM_DATES);
});
