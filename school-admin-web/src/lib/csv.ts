// Shared CSV parsing helpers for student imports (Students-page CSV import and
// the annual rollover import). Extracted verbatim from csv-import-dialog.tsx so
// both flows tokenize files and map headers identically.
//
// The SIS adapter (lib/sis/) builds on `parseDelimited` when it needs the raw
// records — a real CASES21 export can carry junk rows above the header, so the
// header is not always the first record.

export const HEADER_ALIASES: Record<string, string[]> = {
  // `stkey` is CASES21's student key column when an admin exports the ST table
  // directly instead of running the Lumi export-kit query.
  studentId: ['student id', 'studentid', 'student_id', 'id', 'student number', 'stkey', 'st key', 'student key'],
  firstName: ['first name', 'firstname', 'first_name', 'given name', 'given_name', 'first'],
  lastName: ['last name', 'lastname', 'last_name', 'surname', 'family name', 'family_name', 'last'],
  className: ['class', 'class name', 'classname', 'class_name', 'room', 'group', 'home group', 'home_group', 'homegroup', 'home grp'],
  yearLevel: ['year level', 'year', 'yearlevel', 'year_level', 'year lvl', 'grade', 'grade level', 'school year', 'school_year', 'schoolyear'],
  // Only E_MAIL_A is aliased: CASES21's DF table also has E_MAIL_B, and mapping
  // both to one field would let B silently overwrite a populated A. The SIS
  // adapter handles the A → B fallback explicitly.
  parentEmail: ['parent email', 'parent_email', 'parentemail', 'email', 'parent', 'e_mail_a', 'email_a', 'e-mail a'],
  readingLevel: ['reading level', 'readinglevel', 'reading_level', 'level'],
};

/** Normalised form used for header comparisons (case/space/punctuation-loose). */
export function headerKey(header: string): string {
  return header.replace(/^﻿/, '').trim().toLowerCase().replace(/\s+/g, ' ');
}

export function matchHeader(header: string): string | null {
  const normalized = headerKey(header);
  for (const [field, aliases] of Object.entries(HEADER_ALIASES)) {
    if (aliases.includes(normalized)) return field;
  }
  return null;
}

/**
 * Tokenize a delimited file into records (RFC-4180-ish), without deciding which
 * record is the header. Handles quoted fields, escaped quotes (""), newlines
 * inside quotes, CRLF, a UTF-8 BOM, and comma/tab/semicolon delimiters.
 *
 * The old `line.split(delimiter)` shifted every column whenever a field was
 * quoted and contained the delimiter (e.g. a class "Room 1, Building A" or a
 * name "Smith, Jr."), silently corrupting the import.
 */
export function parseDelimited(text: string): string[][] {
  // Strip a UTF-8 BOM if present (Excel adds one).
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);

  const delimiter = detectDelimiter(text);

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

  // Drop blank lines. A real CASES21 export carries one between the header and
  // the first student.
  return records.filter((r) => r.some((c) => c.trim() !== '')).map((r) => r.map((c) => c.trim()));
}

/**
 * Pick the delimiter by majority across the first few lines rather than the
 * first line alone — an export can carry a title row above the header, and a
 * pasted Excel selection is tab-separated.
 */
function detectDelimiter(text: string): string {
  const sample = text.split(/\r?\n/).slice(0, 5).join('\n');
  const count = (ch: string) => sample.split(ch).length - 1;
  const commas = count(',');
  const tabs = count('\t');
  const semis = count(';');
  if (tabs > commas && tabs >= semis) return '\t';
  if (semis > commas && semis > tabs) return ';';
  return ',';
}

export function parseCSV(text: string): { headers: string[]; rows: string[][] } {
  const records = parseDelimited(text);
  if (records.length === 0) return { headers: [], rows: [] };
  return { headers: records[0], rows: records.slice(1) };
}
