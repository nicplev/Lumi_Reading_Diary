// Unit tests for SIS format detection and row shaping. Run with:
//   npx tsx scripts/sis-detect.test.ts
// (No test runner in this package — plain asserts; the script exits non-zero
// on the first failure.)
//
// The CASES21 fixtures reproduce the STRUCTURE of a real export returned by a
// Victorian primary school — uppercase headings, CRLF, a blank record between
// the header and the first student, `N.0` year levels, Foundation as year 0,
// siblings sharing a family email. Every student row below is invented.
// NEVER paste real school data into these fixtures.

import assert from 'node:assert/strict';
import { parseDelimited, matchHeader } from '../src/lib/csv';
import { adaptSisRecords, detectSis } from '../src/lib/sis/detect';

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

/** Exactly the shape the export kit's query produces, blank record and all. */
const CASES21_KIT = [
  'STUDENT ID,FIRST NAME,LAST NAME,CLASS NAME,YEAR LEVEL,PARENT EMAIL',
  ',,,,,',
  'ABC1001,Ada,Nguyen,00A,0.0,nguyen.family@example.com',
  'ABC1002,Bo,Nguyen,00A,0.0,nguyen.family@example.com',
  'ABC1003,Cy,Rossi,04B,4.0,rossi.home@example.com',
].join('\r\n');

const parse = (text: string) => adaptSisRecords(parseDelimited(text));

// ── Detection ────────────────────────────────────────────────────────────────

test('uppercase kit headings map to Lumi fields', () => {
  assert.equal(matchHeader('STUDENT ID'), 'studentId');
  assert.equal(matchHeader('FIRST NAME'), 'firstName');
  assert.equal(matchHeader('LAST NAME'), 'lastName');
  assert.equal(matchHeader('CLASS NAME'), 'className');
  assert.equal(matchHeader('YEAR LEVEL'), 'yearLevel');
  assert.equal(matchHeader('PARENT EMAIL'), 'parentEmail');
});

test('a kit export is identified by its rounded year levels', () => {
  const { detection } = parse(CASES21_KIT);
  assert.equal(detection.format, 'cases21');
  assert.equal(detection.headerRowIndex, 0);
  assert.deepEqual(detection.missingFields, []);
});

test('the same columns without the rounding artefact read as the Lumi template', () => {
  const { detection } = parse(
    ['Student ID,First Name,Last Name,Class Name,Year Level,Parent Email', 'S1,Ada,Nguyen,Prep A,Prep,a@example.com'].join('\n')
  );
  assert.equal(detection.format, 'lumi_standard');
});

test('raw CASES21 table columns are recognised', () => {
  const { detection } = parse(
    [
      'STKEY,SURNAME,FIRST_NAME,HOME_GROUP,SCHOOL_YEAR,STATUS,E_MAIL_A,E_MAIL_B',
      'ABC1001,Nguyen,Ada,00A,0,ACTV,a@example.com,',
    ].join('\n')
  );
  assert.equal(detection.format, 'cases21_raw');
  assert.deepEqual(detection.missingFields, []);
});

test('junk rows above the heading row are skipped, not treated as headers', () => {
  const result = parse(
    [
      'Student Enrolment Report — printed 12/12/2026',
      'Campus 01',
      'STUDENT ID,FIRST NAME,LAST NAME,CLASS NAME,YEAR LEVEL,PARENT EMAIL',
      'ABC1001,Ada,Nguyen,00A,0.0,a@example.com',
    ].join('\r\n')
  );
  assert.equal(result.detection.headerRowIndex, 2);
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].firstName, 'Ada');
  assert.equal(result.notes.find((n) => n.code === 'junk_rows')?.count, 2);
});

test('a file with no recognisable columns is reported as unknown', () => {
  const { detection } = parse(['Alpha,Beta,Gamma', '1,2,3'].join('\n'));
  assert.equal(detection.format, 'unknown');
  assert.ok(detection.missingFields.includes('firstName'));
});

// ── Row shaping ──────────────────────────────────────────────────────────────

test('the blank record between header and data is dropped', () => {
  const result = parse(CASES21_KIT);
  assert.equal(result.rows.length, 3);
  assert.equal(result.rows[0].studentId, 'ABC1001');
});

test('year levels are decoded, and the decode is reported', () => {
  const result = parse(CASES21_KIT);
  assert.deepEqual(
    result.rows.map((r) => r.yearLevel),
    ['Prep', 'Prep', '4']
  );
  assert.equal(result.notes.find((n) => n.code === 'year_decoded')?.count, 3);
});

test('home groups import verbatim so 00A is not mangled into a year', () => {
  const result = parse(CASES21_KIT);
  assert.deepEqual(
    result.rows.map((r) => r.className),
    ['00A', '00A', '04B']
  );
});

test('siblings sharing a family email are both kept', () => {
  const result = parse(CASES21_KIT);
  assert.equal(result.rows[0].parentEmail, result.rows[1].parentEmail);
  assert.equal(result.rows.filter((r) => r.parentEmail === 'nguyen.family@example.com').length, 2);
});

test('departed students are filtered out of a raw export and counted', () => {
  const result = parse(
    [
      'STKEY,SURNAME,FIRST_NAME,HOME_GROUP,SCHOOL_YEAR,STATUS,E_MAIL_A',
      'ABC1001,Nguyen,Ada,00A,0,ACTV,a@example.com',
      'ABC1002,Rossi,Bo,04B,4,LEFT,b@example.com',
      'ABC1003,Silva,Cy,04B,4,INAC,c@example.com',
    ].join('\n')
  );
  assert.equal(result.rows.length, 1);
  assert.equal(result.notes.find((n) => n.code === 'departed')?.count, 2);
});

test('future enrolments are kept, and flagged so the admin can decide', () => {
  const result = parse(
    [
      'STKEY,SURNAME,FIRST_NAME,HOME_GROUP,SCHOOL_YEAR,STATUS',
      'ABC1001,Nguyen,Ada,00A,0,ACTV',
      'ABC1002,Rossi,Bo,00A,0,FUT',
    ].join('\n')
  );
  assert.equal(result.rows.length, 2);
  assert.equal(result.notes.find((n) => n.code === 'future')?.count, 1);
});

test('the second family email is a fallback, never an override', () => {
  const result = parse(
    [
      'STKEY,SURNAME,FIRST_NAME,HOME_GROUP,SCHOOL_YEAR,E_MAIL_A,E_MAIL_B',
      'ABC1001,Nguyen,Ada,00A,0,primary@example.com,secondary@example.com',
      'ABC1002,Rossi,Bo,00A,0,,secondary-only@example.com',
    ].join('\n')
  );
  assert.equal(result.rows[0].parentEmail, 'primary@example.com');
  assert.equal(result.rows[1].parentEmail, 'secondary-only@example.com');
  assert.equal(result.notes.find((n) => n.code === 'email_fallback')?.count, 1);
});

// ── Input formats ────────────────────────────────────────────────────────────

test('a selection pasted out of Excel (TSV) reads identically', () => {
  const pasted = [
    'STUDENT ID\tFIRST NAME\tLAST NAME\tCLASS NAME\tYEAR LEVEL\tPARENT EMAIL',
    'ABC1001\tAda\tNguyen\t00A\t0.0\ta@example.com',
  ].join('\n');
  const result = parse(pasted);
  assert.equal(result.rows.length, 1);
  assert.deepEqual(result.rows[0], {
    studentId: 'ABC1001',
    firstName: 'Ada',
    lastName: 'Nguyen',
    className: '00A',
    yearLevel: 'Prep',
    parentEmail: 'a@example.com',
    readingLevel: undefined,
  });
});

test('a UTF-8 BOM and quoted commas survive tokenizing', () => {
  const result = parse(
    '﻿Student ID,First Name,Last Name,Class Name,Year Level\r\nS1,Ada,"Nguyen, Jr","Room 1, Building A",4\r\n'
  );
  assert.equal(result.rows[0].lastName, 'Nguyen, Jr');
  assert.equal(result.rows[0].className, 'Room 1, Building A');
  assert.equal(result.rows[0].yearLevel, '4');
});

test('a semicolon-delimited export (European Excel) is tokenized', () => {
  const result = parse(
    ['Student ID;First Name;Last Name;Class Name;Year Level', 'S1;Ada;Nguyen;Prep A;0'].join('\n')
  );
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].className, 'Prep A');
  assert.equal(result.rows[0].yearLevel, 'Prep');
});

test('column order does not matter and extra columns are ignored', () => {
  const result = parse(
    [
      'HOUSE,LAST NAME,FIRST NAME,YEAR LEVEL,CLASS NAME,STUDENT ID,GENDER',
      'Red,Nguyen,Ada,4.0,04B,ABC1001,F',
    ].join('\n')
  );
  assert.deepEqual(result.rows[0], {
    studentId: 'ABC1001',
    firstName: 'Ada',
    lastName: 'Nguyen',
    className: '04B',
    yearLevel: '4',
    parentEmail: undefined,
    readingLevel: undefined,
  });
});

test('a file with only a heading row yields no rows rather than throwing', () => {
  const result = parse('STUDENT ID,FIRST NAME,LAST NAME,CLASS NAME,YEAR LEVEL,PARENT EMAIL\r\n');
  assert.equal(result.rows.length, 0);
});

test('detectSis on an empty record list does not throw', () => {
  const detection = detectSis([]);
  assert.equal(detection.format, 'unknown');
  assert.deepEqual(detection.headers, []);
});

console.log(`\nAll ${testCount} tests passed.`);
