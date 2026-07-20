// Shared CSV parsing helpers for student imports (Students-page CSV import and
// the annual rollover import). Extracted verbatim from csv-import-dialog.tsx so
// both flows tokenize files and map headers identically.

export const HEADER_ALIASES: Record<string, string[]> = {
  studentId: ['student id', 'studentid', 'student_id', 'id', 'student number'],
  firstName: ['first name', 'firstname', 'first_name', 'given name', 'first'],
  lastName: ['last name', 'lastname', 'last_name', 'surname', 'family name', 'last'],
  className: ['class', 'class name', 'classname', 'class_name', 'room', 'group'],
  yearLevel: ['year level', 'year', 'yearlevel', 'year_level', 'year lvl', 'grade', 'grade level'],
  parentEmail: ['parent email', 'parent_email', 'parentemail', 'email', 'parent'],
  readingLevel: ['reading level', 'readinglevel', 'reading_level', 'level'],
};

export function matchHeader(header: string): string | null {
  const normalized = header.toLowerCase().trim();
  for (const [field, aliases] of Object.entries(HEADER_ALIASES)) {
    if (aliases.includes(normalized)) return field;
  }
  return null;
}

// A proper CSV/TSV tokenizer (RFC-4180-ish). The old `line.split(delimiter)`
// shifted every column whenever a field was quoted and contained the delimiter
// (e.g. a class "Room 1, Building A" or a name "Smith, Jr."), silently
// corrupting the import. This handles quoted fields, escaped quotes (""), and
// newlines inside quotes.
export function parseCSV(text: string): { headers: string[]; rows: string[][] } {
  // Strip a UTF-8 BOM if present (Excel adds one).
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);

  const firstLine = text.split(/\r?\n/, 1)[0] ?? '';
  const delimiter = firstLine.includes('\t') && !firstLine.includes(',') ? '\t' : ',';

  const records: string[][] = [];
  let field = '';
  let record: string[] = [];
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } // escaped quote
        else inQuotes = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === delimiter) {
      record.push(field);
      field = '';
    } else if (ch === '\r') {
      // ignore — handled by the \n branch
    } else if (ch === '\n') {
      record.push(field);
      records.push(record);
      field = '';
      record = [];
    } else {
      field += ch;
    }
  }
  // Flush a trailing field/record when the file doesn't end in a newline.
  if (field !== '' || record.length > 0) {
    record.push(field);
    records.push(record);
  }

  // Drop blank lines.
  const nonEmpty = records.filter((r) => r.some((c) => c.trim() !== ''));
  if (nonEmpty.length === 0) return { headers: [], rows: [] };

  const headers = nonEmpty[0].map((h) => h.trim());
  const rows = nonEmpty.slice(1).map((r) => r.map((c) => c.trim()));
  return { headers, rows };
}
