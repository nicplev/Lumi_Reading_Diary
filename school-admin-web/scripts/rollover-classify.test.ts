// Unit tests for the pure rollover classifier. Run with:
//   npx tsx scripts/rollover-classify.test.ts
// (No test runner in this package — plain asserts; the script exits non-zero
// on the first failure.)

import assert from 'node:assert/strict';
import {
  classifyRollover,
  idKey,
  nameKey,
  type ExistingClass,
  type ExistingStudent,
  type RolloverCSVRow,
} from '../src/lib/rollover/classify';

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

// ── Fixtures: a P–2 campus mid-rollover ─────────────────────────────────────
const classes: ExistingClass[] = [
  { docId: 'c-prep', name: 'Prep A', yearLevel: 'Prep', isActive: true },
  { docId: 'c-1a', name: '1A', yearLevel: '1', isActive: true },
  { docId: 'c-2a', name: '2A', yearLevel: '2', isActive: true },
  { docId: 'c-old', name: '1B', yearLevel: '1', isActive: false }, // deactivated last year
];

const student = (over: Partial<ExistingStudent>): ExistingStudent => ({
  docId: 'x',
  externalId: null,
  firstName: 'X',
  lastName: 'X',
  classId: 'c-prep',
  isActive: true,
  yearLevel: null,
  graduated: false,
  hasParentLink: false,
  ...over,
});

const students: ExistingStudent[] = [
  student({ docId: 's-jane', externalId: 'S1001', firstName: 'Jane', lastName: 'Smith', classId: 'c-prep' }),
  student({ docId: 's-tom', externalId: 's1002', firstName: 'Tom', lastName: 'Brown', classId: 'c-1a' }), // lowercase id on file
  student({ docId: 's-mia', externalId: null, firstName: 'Mia', lastName: 'Nguyễn', classId: 'c-1a' }), // no ID, diacritic
  student({ docId: 's-zoe', externalId: 'S1004', firstName: 'Zoe', lastName: 'Park', classId: 'c-2a' }), // year 2 = top → graduates
  student({ docId: 's-arch', externalId: 'S9999', firstName: 'Ari', lastName: 'Stone', classId: 'c-1a', isActive: false }), // archived
  student({ docId: 's-left', externalId: 'S1006', firstName: 'Lee', lastName: 'Chan', classId: 'c-prep' }), // will be missing (leaver)
];

const row = (over: Partial<RolloverCSVRow>): RolloverCSVRow => ({
  firstName: '',
  lastName: '',
  className: '',
  ...over,
});

// ── Normalizers ──────────────────────────────────────────────────────────────
test('idKey uppercases and trims; blank → null', () => {
  assert.equal(idKey('  s1002 '), 'S1002');
  assert.equal(idKey(''), null);
  assert.equal(idKey(undefined), null);
});

test('nameKey strips diacritics, case, extra whitespace', () => {
  assert.equal(nameKey('Nguyễn'), 'nguyen');
  assert.equal(nameKey('  De   La  CRUZ '), 'de la cruz');
});

// ── Buckets ──────────────────────────────────────────────────────────────────
test('exact ID hit → match, case-insensitive, with class/year annotations', () => {
  const r = classifyRollover(
    [row({ studentId: 'S1002', firstName: 'Tom', lastName: 'Brown', className: '2A', yearLevel: '2' })],
    students,
    classes
  );
  const c = r.rows[0];
  assert.equal(c.bucket, 'match');
  assert.equal(c.matchedStudentDocId, 's-tom');
  assert.deepEqual(c.classChanged, { fromClassId: 'c-1a', fromClassName: '1A', toClassName: '2A' });
  assert.deepEqual(c.yearLevelChanged, { from: '1', to: '2' });
  assert.equal(c.offLadder, undefined); // 1 → 2 is the expected step
});

test('off-ladder year level (repeat) is trusted but flagged', () => {
  const r = classifyRollover(
    [row({ studentId: 'S1002', firstName: 'Tom', lastName: 'Brown', className: '1A', yearLevel: '1' })],
    students,
    classes
  );
  const c = r.rows[0];
  assert.equal(c.bucket, 'match');
  assert.equal(c.offLadder, true);
  assert.equal(c.yearLevelChanged, undefined); // same level, no change
});

test('ID hit on archived student → match_archived', () => {
  const r = classifyRollover(
    [row({ studentId: 'S9999', firstName: 'Ari', lastName: 'Stone', className: '1A', yearLevel: '1' })],
    students,
    classes
  );
  assert.equal(r.rows[0].bucket, 'match_archived');
  assert.equal(r.rows[0].matchedStudentDocId, 's-arch');
});

test('no-ID row with exact-name no-ID student → name_suggest (diacritics-insensitive)', () => {
  const r = classifyRollover(
    [row({ firstName: 'Mia', lastName: 'Nguyen', className: '2A', yearLevel: '2' })],
    students,
    classes
  );
  const c = r.rows[0];
  assert.equal(c.bucket, 'name_suggest');
  assert.equal(c.candidates?.length, 1);
  assert.equal(c.candidates?.[0].docId, 's-mia');
  // …and the candidate is annotated on the missing list for the UI.
  const mia = r.missing.find((m) => m.docId === 's-mia');
  assert.deepEqual(mia?.suggestedInRows, [1]);
});

test('row with an unmatched ID still gets name suggestions (ID backfill path)', () => {
  const r = classifyRollover(
    [row({ studentId: 'S7777', firstName: 'Mia', lastName: 'Nguyễn', className: '2A' })],
    students,
    classes
  );
  assert.equal(r.rows[0].bucket, 'name_suggest');
});

test('unknown row → new; same-name-different-ID only warns', () => {
  const r = classifyRollover(
    [
      row({ studentId: 'P2001', firstName: 'New', lastName: 'Prep', className: 'Prep A', yearLevel: 'Prep', parentEmail: 'p@x.com' }),
      row({ studentId: 'S8888', firstName: 'Jane', lastName: 'Smith', className: '1A' }), // Jane exists with S1001
    ],
    students,
    classes
  );
  assert.equal(r.rows[0].bucket, 'new');
  assert.equal(r.rows[0].warnings.length, 0);
  assert.equal(r.rows[1].bucket, 'new');
  assert.match(r.rows[1].warnings[0], /different Student ID/);
});

test('duplicate ID in file → error on every copy', () => {
  const r = classifyRollover(
    [
      row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: '1A' }),
      row({ studentId: 's1001', firstName: 'Janet', lastName: 'Smith', className: '1A' }),
    ],
    students,
    classes
  );
  assert.equal(r.rows[0].bucket, 'error');
  assert.equal(r.rows[1].bucket, 'error');
});

test('missing required fields → error row', () => {
  const r = classifyRollover([row({ firstName: 'OnlyFirst', className: '1A' })], students, classes);
  assert.equal(r.rows[0].bucket, 'error');
});

test('two ACTIVE students sharing an ID → error, never auto-picked', () => {
  const corrupt = [...students, student({ docId: 's-dup', externalId: 'S1001', firstName: 'Other', lastName: 'Kid' })];
  const r = classifyRollover(
    [row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: '1A' })],
    corrupt,
    classes
  );
  assert.equal(r.rows[0].bucket, 'error');
  assert.match(r.rows[0].error!, /share Student ID/);
});

test('name mismatch on ID match is flagged, ID wins', () => {
  const r = classifyRollover(
    [row({ studentId: 'S1001', firstName: 'Janey', lastName: 'Smith', className: '1A' })],
    students,
    classes
  );
  assert.equal(r.rows[0].bucket, 'match');
  assert.equal(r.rows[0].nameMismatch?.storedName, 'Jane Smith');
});

// ── Missing split ────────────────────────────────────────────────────────────
test("graduating uses the school's own top year (P–2 campus: Year 2 graduates, Prep leaver)", () => {
  const r = classifyRollover(
    [row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: '1A', yearLevel: '1' })],
    students,
    classes
  );
  const zoe = r.missing.find((m) => m.docId === 's-zoe');
  const lee = r.missing.find((m) => m.docId === 's-left');
  const tom = r.missing.find((m) => m.docId === 's-tom');
  assert.equal(zoe?.disposition, 'graduating'); // year 2 = school top
  assert.equal(lee?.disposition, 'leaver'); // Prep, not top
  assert.equal(tom?.disposition, 'leaver'); // year 1
  assert.ok(!r.missing.some((m) => m.docId === 's-jane')); // claimed by the row
  assert.ok(!r.missing.some((m) => m.docId === 's-arch')); // archived students never "missing"
});

// ── Class analysis ───────────────────────────────────────────────────────────
test('class rename: new class in toCreate, old class flagged empty; inactive name clash detected', () => {
  const rows = [
    // Everyone in 1A moves to the renamed "2 Apple"; 1A gains nobody.
    row({ studentId: 'S1002', firstName: 'Tom', lastName: 'Brown', className: '2 Apple', yearLevel: '2' }),
    row({ firstName: 'Mia', lastName: 'Nguyen', className: '2 Apple', yearLevel: '2' }), // suggest — s-mia still "missing" until confirmed
    // Reuse of a deactivated class's name.
    row({ studentId: 'P3001', firstName: 'Kim', lastName: 'Ito', className: '1B', yearLevel: '1' }),
  ];
  const r = classifyRollover(rows, students, classes);

  const created = r.classes.toCreate.map((c) => c.name).sort();
  assert.deepEqual(created, ['1B', '2 Apple']);
  const apple = r.classes.toCreate.find((c) => c.name === '2 Apple');
  assert.equal(apple?.yearLevel, '2');
  assert.equal(apple?.yearLevelConflict, false);
  assert.deepEqual(r.classes.inactiveNameClash, [{ name: '1B', inactiveClassId: 'c-old' }]);

  // 1A: Tom moves away, Mia unconfirmed (missing) → empty AND whole-class…
  // no: Tom matched, so 1A is not whole-class-missing, but IS empty-after.
  assert.ok(r.classes.emptyAfterImport.some((c) => c.docId === 'c-1a'));
  assert.ok(!r.classes.wholeClassMissing.some((c) => c.docId === 'c-1a'));
  // 2A: Zoe missing entirely → whole-class-missing.
  assert.ok(r.classes.wholeClassMissing.some((c) => c.docId === 'c-2a'));
});

test('idempotent re-import: everything matches, no class changes, exact missing set', () => {
  const rows = [
    row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: 'Prep A', yearLevel: 'Prep' }),
    row({ studentId: 'S1002', firstName: 'Tom', lastName: 'Brown', className: '1A', yearLevel: '1' }),
    row({ studentId: 'S1006', firstName: 'Lee', lastName: 'Chan', className: 'Prep A', yearLevel: 'Prep' }),
  ];
  const r = classifyRollover(rows, students, classes);
  assert.equal(r.stats.match, 3);
  assert.equal(r.stats.new, 0);
  // Same classes as on file → no classChanged annotations.
  assert.ok(r.rows.every((c) => c.classChanged === undefined));
  // Mia (name-suggest only, unconfirmed) and Zoe (graduating) remain missing —
  // that's for the admin to resolve; the classifier never silently drops them.
  assert.deepEqual(r.missing.map((m) => m.docId).sort(), ['s-mia', 's-zoe']);
});

test('graduated flag forces graduating disposition regardless of year', () => {
  const withFlag = [...students, student({ docId: 's-grad', firstName: 'Gia', lastName: 'Held', classId: 'c-prep', graduated: true })];
  const r = classifyRollover([row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: 'Prep A' })], withFlag, classes);
  assert.equal(r.missing.find((m) => m.docId === 's-grad')?.disposition, 'graduating');
});

test('stats: idless importable rows counted', () => {
  const r = classifyRollover(
    [
      row({ firstName: 'A', lastName: 'B', className: '1A' }),
      row({ studentId: 'S1001', firstName: 'Jane', lastName: 'Smith', className: '1A' }),
      row({ firstName: '', lastName: '', className: '' }), // error — not counted as idless
    ],
    students,
    classes
  );
  assert.equal(r.stats.idlessRows, 1);
  assert.equal(r.stats.error, 1);
});

console.log(`\nAll ${testCount} tests passed.`);
