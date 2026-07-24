// Unit tests for year-level normalisation. Run with:
//   npx tsx scripts/year-ladder.test.ts
// (No test runner in this package — plain asserts; the script exits non-zero
// on the first failure.)
//
// The numeric cases exist because CASES21 emits ROUND(SCHOOL_YEAR,0), which
// renders whole years as "0.0".."6.0", and stores Foundation as year 0. Before
// this decoding, every row of a real export failed isLadderYearLevel and was
// saved verbatim as "0.0".

import assert from 'node:assert/strict';
import {
  isLadderYearLevel,
  nextYearLevel,
  normalizeYearLevel,
  yearLevelForRenewal,
} from '../src/lib/year-ladder';

let testCount = 0;
function test(name: string, fn: () => void) {
  testCount++;
  try {
    fn();
    console.log(`  ✓ ${name}`);
  } catch (err) {
    console.error(`  ✗ ${name}`);
    throw err;
  }
}

test('prep synonyms normalise to Prep', () => {
  for (const raw of ['Prep', 'prep', ' PREP ', 'Foundation', 'kinder', 'K', 'f']) {
    assert.equal(normalizeYearLevel(raw), 'Prep', raw);
  }
});

test('CASES21 rounded decimals decode to ladder rungs', () => {
  assert.equal(normalizeYearLevel('0.0'), 'Prep');
  assert.equal(normalizeYearLevel('1.0'), '1');
  assert.equal(normalizeYearLevel('4.0'), '4');
  assert.equal(normalizeYearLevel('6.00'), '6');
});

test('year 0 is Foundation however it is written', () => {
  for (const raw of ['0', '00', '0.0', 'Year 0', 'yr 0']) {
    assert.equal(normalizeYearLevel(raw), 'Prep', raw);
  }
});

test('zero-padded and worded levels normalise', () => {
  assert.equal(normalizeYearLevel('04'), '4');
  assert.equal(normalizeYearLevel('Year 4'), '4');
  assert.equal(normalizeYearLevel('Yr4'), '4');
  assert.equal(normalizeYearLevel('Y 4'), '4');
  assert.equal(normalizeYearLevel('Grade 4'), '4');
  assert.equal(normalizeYearLevel('Gr.4'), '4');
  assert.equal(normalizeYearLevel('Year Prep'), 'Prep');
});

test('unrecognised labels pass through trimmed, not mangled', () => {
  assert.equal(normalizeYearLevel('  Middle Primary '), 'Middle Primary');
  assert.equal(normalizeYearLevel('4.5'), '4.5');
  assert.equal(normalizeYearLevel('00A'), '00A');
  assert.equal(normalizeYearLevel(''), '');
});

test('off-ladder numbers normalise but stay off the ladder', () => {
  // Secondary years are decoded consistently, but must not be treated as rungs.
  assert.equal(normalizeYearLevel('7.0'), '7');
  assert.equal(isLadderYearLevel('7.0'), false);
  assert.equal(isLadderYearLevel('10'), false);
});

test('CASES21 forms are recognised as ladder rungs', () => {
  assert.equal(isLadderYearLevel('0.0'), true);
  assert.equal(isLadderYearLevel('4.0'), true);
  assert.equal(isLadderYearLevel(''), false);
  assert.equal(isLadderYearLevel(null), false);
});

test('a CASES21 Prep bumps to Year 1 on renewal', () => {
  assert.deepEqual(nextYearLevel('0.0'), { next: '1', graduated: false, changed: true });
  assert.deepEqual(nextYearLevel('4.0'), { next: '5', graduated: false, changed: true });
});

test('a CASES21 Year 6 graduates rather than bumping', () => {
  assert.deepEqual(nextYearLevel('6.0'), { next: '6', graduated: true, changed: false });
});

test('the import authority marker still suppresses the double bump', () => {
  const r = yearLevelForRenewal('Prep', 2027, 2027);
  assert.equal(r.next, 'Prep');
  assert.equal(r.changed, false);
  assert.equal(r.setByImport, true);
});

console.log(`\nAll ${testCount} tests passed.`);
