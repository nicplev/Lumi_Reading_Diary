// SIS (student information system) format detection and row shaping.
//
// Sits between lib/csv.ts (tokenizing) and the import flows (rollover wizard,
// Students-page CSV dialog), so an admin can hand us the file their SIS
// produced instead of hand-building the Lumi template.
//
// Pure module — no DOM, no Firestore, relative imports only — so
// scripts/sis-detect.test.ts can run it under `npx tsx`. Browser-side file
// reading (including .xlsx) lives in ./read-input.ts.
//
// Shapes confirmed against a real CASES21 return from a Victorian primary
// school (structure only; none of that school's data appears here):
//   - the SQL worksheet UPPERCASES the `AS [alias]` names
//   - `ROUND(SCHOOL_YEAR,0)` renders as `0.0` … `6.0`, and Foundation is year 0
//   - a fully blank record sits between the header and the first student
//   - siblings repeat the same family email

import { matchHeader, headerKey } from '../csv';
import { normalizeYearLevel } from '../year-ladder';

/** Columns of CASES21's own ST/DF tables, for admins who export them raw. */
const CASES21_RAW_SIGNATURE = ['stkey', 'surname', 'first_name', 'home_group', 'school_year'];

/** Second family email in CASES21's DF table — a fallback, never an override. */
const EMAIL_FALLBACK_KEYS = ['e_mail_b', 'email_b', 'e-mail b', 'parent email 2', 'parent_email_2'];

const STATUS_KEYS = ['status', 'st_status', 'student status'];

/** CASES21 enrolment statuses that mean "not on the roster any more". */
const DEPARTED_STATUSES = ['left', 'inac', 'inactive', 'del', 'deleted', 'arch', 'archived'];
/** Enrolled-but-not-started — kept, because a summer rollover needs them. */
const FUTURE_STATUSES = ['fut', 'future'];

/** The six columns the Lumi export kit produces. */
const KIT_FIELDS = ['studentId', 'firstName', 'lastName', 'className', 'yearLevel', 'parentEmail'];

/** The `ROUND(SCHOOL_YEAR,0)` artefact — a decisive CASES21 tell. */
const ROUNDED_DECIMAL = /^\d+\.0+$/;

export type SisFormat = 'cases21' | 'cases21_raw' | 'lumi_standard' | 'generic' | 'unknown';

export interface SisDetection {
  format: SisFormat;
  /** Human label for the "Detected …" banner. */
  label: string;
  /** Index into the parsed records of the row used as the header. */
  headerRowIndex: number;
  headers: string[];
  /** Field name → every column index that maps to it, in file order. */
  columnMap: Record<string, number[]>;
  statusColumn: number | null;
  emailFallbackColumns: number[];
  /** Fields the file has no column for. */
  missingFields: string[];
}

export interface SisRow {
  studentId?: string;
  firstName: string;
  lastName: string;
  className: string;
  yearLevel?: string;
  parentEmail?: string;
  readingLevel?: string;
}

export interface SisNote {
  /** Machine tag, so the UI can style/aggregate without parsing prose. */
  code:
    | 'sheet'
    | 'junk_rows'
    | 'departed'
    | 'future'
    | 'blank_rows'
    | 'year_decoded'
    | 'email_fallback';
  message: string;
  count: number;
}

export interface SisParseResult {
  detection: SisDetection;
  rows: SisRow[];
  notes: SisNote[];
  /** Records below the header, before any were dropped. */
  dataRecordCount: number;
}

// ── Detection ────────────────────────────────────────────────────────────────

/**
 * Find the header row and work out which SIS produced the file.
 *
 * The header is not assumed to be the first record: exports can carry a report
 * title or filter summary above it. We score the first few records by how many
 * Lumi fields their cells name, and take the best.
 */
export function detectSis(records: string[][]): SisDetection {
  let bestIndex = 0;
  let bestScore = -1;

  const scanLimit = Math.min(records.length, 10);
  for (let i = 0; i < scanLimit; i++) {
    const fields = new Set<string>();
    for (const cell of records[i]) {
      const field = matchHeader(cell);
      if (field) fields.add(field);
    }
    // A header must name at least two fields, one of which identifies a person.
    const identifies = fields.has('firstName') || fields.has('lastName') || fields.has('studentId');
    const score = fields.size >= 2 && identifies ? fields.size : 0;
    if (score > bestScore) {
      bestScore = score;
      bestIndex = i;
    }
  }

  const headers = records[bestIndex] ?? [];
  const keys = headers.map(headerKey);

  const columnMap: Record<string, number[]> = {};
  headers.forEach((header, index) => {
    const field = matchHeader(header);
    if (!field) return;
    (columnMap[field] ??= []).push(index);
  });

  const statusColumn = keys.findIndex((k) => STATUS_KEYS.includes(k));
  const emailFallbackColumns = keys
    .map((k, i) => (EMAIL_FALLBACK_KEYS.includes(k) ? i : -1))
    .filter((i) => i !== -1);

  const rawHits = CASES21_RAW_SIGNATURE.filter((c) => keys.includes(c)).length;
  const hasKitColumns = KIT_FIELDS.every((f) => columnMap[f]?.length);

  // Value-level tell: the SQL worksheet's ROUND() renders whole years as "4.0".
  const yearColumns = columnMap.yearLevel ?? [];
  const roundedYears = yearColumns.length
    ? records
        .slice(bestIndex + 1)
        .some((r) => yearColumns.some((c) => ROUNDED_DECIMAL.test((r[c] ?? '').trim())))
    : false;

  let format: SisFormat;
  let label: string;
  if (rawHits >= 3) {
    format = 'cases21_raw';
    label = 'CASES21 (raw table export)';
  } else if (hasKitColumns && roundedYears) {
    format = 'cases21';
    label = 'CASES21 export kit';
  } else if (hasKitColumns) {
    format = 'lumi_standard';
    label = 'Lumi standard columns';
  } else if (bestScore > 0) {
    format = 'generic';
    label = 'Recognised columns';
  } else {
    format = 'unknown';
    label = 'Unrecognised columns';
  }

  return {
    format,
    label,
    headerRowIndex: bestIndex,
    headers,
    columnMap,
    statusColumn: statusColumn === -1 ? null : statusColumn,
    emailFallbackColumns,
    missingFields: KIT_FIELDS.filter((f) => !columnMap[f]?.length),
  };
}

// ── Row shaping ──────────────────────────────────────────────────────────────

/**
 * Turn tokenized records into import rows, applying the SIS-specific handling
 * the review step shouldn't have to know about: departed students dropped,
 * numeric year levels decoded, the second family email used only as a fallback.
 */
export function adaptSisRecords(records: string[][], detection?: SisDetection): SisParseResult {
  const det = detection ?? detectSis(records);
  const dataRecords = records.slice(det.headerRowIndex + 1);
  const notes: SisNote[] = [];

  if (det.headerRowIndex > 0) {
    notes.push({
      code: 'junk_rows',
      count: det.headerRowIndex,
      message: `Ignored ${det.headerRowIndex} row${det.headerRowIndex === 1 ? '' : 's'} above the column headings`,
    });
  }

  /** First non-empty value across every column mapped to this field. */
  const pick = (record: string[], field: string): string => {
    for (const index of det.columnMap[field] ?? []) {
      const value = (record[index] ?? '').trim();
      if (value !== '') return value;
    }
    return '';
  };

  const rows: SisRow[] = [];
  let departed = 0;
  let future = 0;
  let blank = 0;
  let yearsDecoded = 0;
  let emailFallbacks = 0;

  for (const record of dataRecords) {
    if (det.statusColumn !== null) {
      const status = (record[det.statusColumn] ?? '').trim().toLowerCase();
      if (DEPARTED_STATUSES.includes(status)) {
        departed++;
        continue;
      }
      if (FUTURE_STATUSES.includes(status)) future++;
    }

    const firstName = pick(record, 'firstName');
    const lastName = pick(record, 'lastName');
    const className = pick(record, 'className');
    const studentId = pick(record, 'studentId');

    if (!firstName && !lastName && !className && !studentId) {
      blank++;
      continue;
    }

    let parentEmail = pick(record, 'parentEmail');
    if (!parentEmail) {
      for (const index of det.emailFallbackColumns) {
        const value = (record[index] ?? '').trim();
        if (value !== '') {
          parentEmail = value;
          emailFallbacks++;
          break;
        }
      }
    }

    const rawYear = pick(record, 'yearLevel');
    const yearLevel = rawYear ? normalizeYearLevel(rawYear) : '';
    if (rawYear && yearLevel !== rawYear) yearsDecoded++;

    rows.push({
      studentId: studentId || undefined,
      firstName,
      lastName,
      className,
      yearLevel: yearLevel || undefined,
      parentEmail: parentEmail || undefined,
      readingLevel: pick(record, 'readingLevel') || undefined,
    });
  }

  if (departed > 0) {
    notes.push({
      code: 'departed',
      count: departed,
      message: `Skipped ${departed} student${departed === 1 ? '' : 's'} whose enrolment status is not active`,
    });
  }
  if (future > 0) {
    notes.push({
      code: 'future',
      count: future,
      message: `Included ${future} future enrolment${future === 1 ? '' : 's'} (status FUT) — exclude them in the review step if they shouldn't start yet`,
    });
  }
  if (blank > 0) {
    notes.push({
      code: 'blank_rows',
      count: blank,
      message: `Skipped ${blank} blank row${blank === 1 ? '' : 's'}`,
    });
  }
  if (yearsDecoded > 0) {
    notes.push({
      code: 'year_decoded',
      count: yearsDecoded,
      message: `Converted ${yearsDecoded} year level${yearsDecoded === 1 ? '' : 's'} from your system's format (year 0 = Prep)`,
    });
  }
  if (emailFallbacks > 0) {
    notes.push({
      code: 'email_fallback',
      count: emailFallbacks,
      message: `Used the second family email for ${emailFallbacks} student${emailFallbacks === 1 ? '' : 's'} with no primary email`,
    });
  }

  return { detection: det, rows, notes, dataRecordCount: dataRecords.length };
}
