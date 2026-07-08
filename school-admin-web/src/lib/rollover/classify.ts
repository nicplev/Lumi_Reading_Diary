// Pure classification engine for the annual rollover import. No Firestore
// imports — lib/firestore/rollover.ts loads the school data and projects it
// into the shapes below; this module just decides what each CSV row means.
// Unit-tested by scripts/rollover-classify.test.ts (npx tsx), which is why
// everything here (including the year-ladder import) must stay side-effect
// free.

import { nextYearLevel, normalizeYearLevel, isLadderYearLevel, YEAR_LADDER } from '../year-ladder';

// ── Inputs ───────────────────────────────────────────────────────────────────

/** One parsed CSV row (post lib/csv.ts header mapping). */
export interface RolloverCSVRow {
  studentId?: string;
  firstName: string;
  lastName: string;
  className: string;
  yearLevel?: string;
  parentEmail?: string;
  readingLevel?: string;
}

/** Projection of an existing student doc (built by previewRollover). */
export interface ExistingStudent {
  docId: string;
  /** External SIS id (`studentId` field), null/'' when never captured. */
  externalId: string | null;
  firstName: string;
  lastName: string;
  classId: string;
  isActive: boolean;
  /** Individual override at additionalInfo.yearLevel (rare pre-import). */
  yearLevel: string | null;
  /** additionalInfo.graduated === true */
  graduated: boolean;
  /** parentIds.length > 0 */
  hasParentLink: boolean;
}

/** Projection of an existing class doc. */
export interface ExistingClass {
  docId: string;
  name: string;
  yearLevel: string | null;
  isActive: boolean;
}

// ── Outputs ──────────────────────────────────────────────────────────────────

export type RowBucket = 'match' | 'match_archived' | 'name_suggest' | 'new' | 'error';

export interface NameSuggestCandidate {
  docId: string;
  name: string;
  classId: string;
  className: string | null;
  /** Effective year level (individual override, else class label). */
  yearLevel: string | null;
  /** Two or more candidates share this name — extra caution in the UI. */
  sharedName: boolean;
}

export interface ClassifiedRow {
  /** 1-based data-row number (header excluded), for error reporting. */
  rowIndex: number;
  csv: RolloverCSVRow;
  bucket: RowBucket;
  /** match / match_archived: the student this row resolves to. */
  matchedStudentDocId?: string;
  matchedStudentName?: string;
  /** name_suggest: existing no-ID students the admin may confirm. */
  candidates?: NameSuggestCandidate[];
  /** Annotations for the review UI. */
  classChanged?: { fromClassId: string; fromClassName: string | null; toClassName: string };
  yearLevelChanged?: { from: string | null; to: string };
  /** CSV year level isn't the expected ladder step from the current one. */
  offLadder?: boolean;
  /** CSV year level isn't a recognised ladder rung (accepted verbatim). */
  unknownYearLevel?: boolean;
  /** ID matched but the CSV name differs from the stored one (ID wins). */
  nameMismatch?: { storedName: string };
  warnings: string[];
  /** bucket === 'error' only. */
  error?: string;
}

export interface MissingStudent {
  docId: string;
  name: string;
  externalId: string | null;
  classId: string;
  className: string | null;
  effectiveYearLevel: string | null;
  /** Default disposition — the admin can flip it or keep the student active. */
  disposition: 'graduating' | 'leaver';
  /** Rows in which this student appears as a name-suggest candidate; if the
   *  admin confirms one, the UI removes the student from the missing list. */
  suggestedInRows: number[];
}

export interface ClassAnalysis {
  /** CSV classes with no active class of that name — will be auto-created. */
  toCreate: { name: string; yearLevel: string | null; rowCount: number; yearLevelConflict: boolean }[];
  /** Active classes that end the import with no students and gain none —
   *  the class-rename signal; offered as opt-in deactivation. */
  emptyAfterImport: { docId: string; name: string; memberCount: number }[];
  /** Active classes none of whose members appear in the CSV — typo guard. */
  wholeClassMissing: { docId: string; name: string; memberCount: number }[];
  /** CSV classes whose name only matches a DEACTIVATED class (a new one will
   *  be created; the old one stays soft-deleted). */
  inactiveNameClash: { name: string; inactiveClassId: string }[];
}

export interface RolloverClassification {
  rows: ClassifiedRow[];
  missing: MissingStudent[];
  classes: ClassAnalysis;
  stats: {
    match: number;
    matchArchived: number;
    nameSuggest: number;
    new: number;
    error: number;
    missingGraduating: number;
    missingLeaver: number;
    /** Importable rows with no external Student ID (duplicate-risk banner). */
    idlessRows: number;
    activeStudentCount: number;
  };
}

// ── Normalizers ──────────────────────────────────────────────────────────────

/** External-ID matching key: SIS exports vary in case/padding. */
export function idKey(raw: string | null | undefined): string | null {
  const t = (raw ?? '').trim().toUpperCase();
  return t === '' ? null : t;
}

/** Name matching key: diacritics-insensitive, case/whitespace-insensitive. */
export function nameKey(raw: string): string {
  return raw
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '') // strip combining diacritical marks
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** Class find-or-create key — must mirror importStudents' classMap. */
export function classKey(raw: string): string {
  return raw.trim().toLowerCase();
}

function fullNameKey(first: string, last: string): string {
  return `${nameKey(first)}|${nameKey(last)}`;
}

// ── Classification ───────────────────────────────────────────────────────────

export function classifyRollover(
  csvRows: RolloverCSVRow[],
  students: ExistingStudent[],
  classes: ExistingClass[]
): RolloverClassification {
  const classById = new Map(classes.map((c) => [c.docId, c]));
  const activeClassByKey = new Map<string, ExistingClass>();
  const inactiveClassByKey = new Map<string, ExistingClass>();
  for (const c of classes) {
    (c.isActive ? activeClassByKey : inactiveClassByKey).set(classKey(c.name), c);
  }

  const effectiveYearLevel = (s: ExistingStudent): string | null =>
    s.yearLevel?.trim() || classById.get(s.classId)?.yearLevel?.trim() || null;

  // Student indexes.
  const activeById = new Map<string, ExistingStudent[]>();
  const archivedById = new Map<string, ExistingStudent[]>();
  const noIdActiveByName = new Map<string, ExistingStudent[]>();
  const activeWithIdByName = new Map<string, ExistingStudent[]>();
  for (const s of students) {
    const key = idKey(s.externalId);
    if (key) {
      const map = s.isActive ? activeById : archivedById;
      const list = map.get(key) ?? [];
      list.push(s);
      map.set(key, list);
    }
    if (s.isActive) {
      const nk = fullNameKey(s.firstName, s.lastName);
      const map = key ? activeWithIdByName : noIdActiveByName;
      const list = map.get(nk) ?? [];
      list.push(s);
      map.set(nk, list);
    }
  }

  // CSV-level duplicate detection.
  const idCounts = new Map<string, number>();
  const idlessNameCounts = new Map<string, number>();
  for (const row of csvRows) {
    const key = idKey(row.studentId);
    if (key) {
      idCounts.set(key, (idCounts.get(key) ?? 0) + 1);
    } else if (row.firstName && row.lastName) {
      const nk = fullNameKey(row.firstName, row.lastName);
      idlessNameCounts.set(nk, (idlessNameCounts.get(nk) ?? 0) + 1);
    }
  }

  const rows: ClassifiedRow[] = [];
  /** docId → row index that claimed it (match / match_archived). */
  const claimed = new Map<string, number>();
  /** candidate docId → row indexes that suggest it. */
  const suggested = new Map<string, number[]>();

  for (let i = 0; i < csvRows.length; i++) {
    const csv = csvRows[i];
    const rowIndex = i + 1;
    const out: ClassifiedRow = { rowIndex, csv, bucket: 'new', warnings: [] };
    rows.push(out);

    // Required fields.
    if (!csv.firstName?.trim() || !csv.lastName?.trim() || !csv.className?.trim()) {
      out.bucket = 'error';
      out.error = 'Missing required fields (First Name, Last Name, Class Name)';
      continue;
    }

    const key = idKey(csv.studentId);

    // Duplicate external ID within the file — integrity error on ALL copies.
    if (key && (idCounts.get(key) ?? 0) > 1) {
      out.bucket = 'error';
      out.error = `Student ID "${csv.studentId?.trim()}" appears more than once in the file`;
      continue;
    }

    // Year-level sanity (annotation only; unknown labels import verbatim).
    const csvYear = csv.yearLevel?.trim() || null;
    if (csvYear && !isLadderYearLevel(csvYear)) {
      out.unknownYearLevel = true;
      out.warnings.push(`Year level "${csvYear}" isn't a standard level (Prep–6) — it will be saved as written`);
    }

    if (key) {
      const activeHits = activeById.get(key) ?? [];
      if (activeHits.length > 1) {
        // Two ACTIVE students share this external id — corrupt data we must
        // not guess about.
        out.bucket = 'error';
        out.error = `Two existing students share Student ID "${csv.studentId?.trim()}" — fix this on the Students page first`;
        continue;
      }
      if (activeHits.length === 1) {
        const s = activeHits[0];
        out.bucket = 'match';
        out.matchedStudentDocId = s.docId;
        out.matchedStudentName = `${s.firstName} ${s.lastName}`.trim();
        claimed.set(s.docId, rowIndex);
        annotateMatch(out, s, csv, csvYear, classById, effectiveYearLevel);
        continue;
      }
      const archivedHits = archivedById.get(key) ?? [];
      if (archivedHits.length > 0) {
        const s = archivedHits[0];
        out.bucket = 'match_archived';
        out.matchedStudentDocId = s.docId;
        out.matchedStudentName = `${s.firstName} ${s.lastName}`.trim();
        claimed.set(s.docId, rowIndex);
        annotateMatch(out, s, csv, csvYear, classById, effectiveYearLevel);
        if (out.nameMismatch) {
          out.warnings.push(
            `Archived student with this ID is named "${out.nameMismatch.storedName}" — if this is a different child, reject the restore`
          );
        }
        continue;
      }
      // ID present but no hit anywhere — fall through to name suggestion.
    }

    // No usable ID hit: suggest exact-name matches among no-ID students.
    const nk = fullNameKey(csv.firstName, csv.lastName);
    const candidates = noIdActiveByName.get(nk) ?? [];
    if (candidates.length > 0) {
      out.bucket = 'name_suggest';
      out.candidates = candidates.map((s) => ({
        docId: s.docId,
        name: `${s.firstName} ${s.lastName}`.trim(),
        classId: s.classId,
        className: classById.get(s.classId)?.name ?? null,
        yearLevel: effectiveYearLevel(s),
        sharedName: candidates.length > 1,
      }));
      if (candidates.length > 1) {
        out.warnings.push('Two or more existing students share this name — confirm carefully');
      }
      for (const s of candidates) {
        const list = suggested.get(s.docId) ?? [];
        list.push(rowIndex);
        suggested.set(s.docId, list);
      }
    } else {
      out.bucket = 'new';
      // Same name exists with a DIFFERENT external id — likely an SIS export
      // mismatch worth a look, but never auto-merged.
      const idClash = activeWithIdByName.get(nk) ?? [];
      if (idClash.length > 0) {
        out.warnings.push(
          `An existing student named "${idClash[0].firstName} ${idClash[0].lastName}" has a different Student ID (${idClash[0].externalId}) — check the export if this is the same child`
        );
      }
    }

    if (!key) {
      if ((idlessNameCounts.get(nk) ?? 0) > 1) {
        out.warnings.push('Another row without a Student ID has this exact name — possible duplicate row');
      }
      out.warnings.push('No Student ID — next year this student can only be matched by name');
    }
  }

  // ── Missing students (active, unclaimed by any row) ───────────────────────
  // School's own top year: the highest ladder rung among active class labels.
  // Covers e.g. P–2 campuses where Year 2 is the graduating year; falls back
  // to the ladder top ('6') when no class carries a recognised label.
  let topYearIdx = -1;
  for (const c of classes) {
    if (!c.isActive || !c.yearLevel) continue;
    const idx = YEAR_LADDER.indexOf(normalizeYearLevel(c.yearLevel));
    if (idx > topYearIdx) topYearIdx = idx;
  }

  const missing: MissingStudent[] = [];
  for (const s of students) {
    if (!s.isActive || claimed.has(s.docId)) continue;
    const eff = effectiveYearLevel(s);
    const effIdx = eff ? YEAR_LADDER.indexOf(normalizeYearLevel(eff)) : -1;
    const graduating =
      s.graduated ||
      (effIdx !== -1 && effIdx === YEAR_LADDER.length - 1) ||
      (effIdx !== -1 && topYearIdx !== -1 && effIdx === topYearIdx);
    missing.push({
      docId: s.docId,
      name: `${s.firstName} ${s.lastName}`.trim(),
      externalId: s.externalId,
      classId: s.classId,
      className: classById.get(s.classId)?.name ?? null,
      effectiveYearLevel: eff,
      disposition: graduating ? 'graduating' : 'leaver',
      suggestedInRows: suggested.get(s.docId) ?? [],
    });
  }
  const missingSet = new Set(missing.map((m) => m.docId));

  // ── Class analysis ─────────────────────────────────────────────────────────
  const csvClassAgg = new Map<string, { name: string; yearLevels: Map<string, number>; rowCount: number }>();
  for (const row of rows) {
    if (row.bucket === 'error') continue;
    const ck = classKey(row.csv.className);
    const agg = csvClassAgg.get(ck) ?? { name: row.csv.className.trim(), yearLevels: new Map(), rowCount: 0 };
    agg.rowCount++;
    const yl = row.csv.yearLevel?.trim();
    if (yl) {
      const norm = isLadderYearLevel(yl) ? normalizeYearLevel(yl) : yl;
      agg.yearLevels.set(norm, (agg.yearLevels.get(norm) ?? 0) + 1);
    }
    csvClassAgg.set(ck, agg);
  }

  const toCreate: ClassAnalysis['toCreate'] = [];
  const inactiveNameClash: ClassAnalysis['inactiveNameClash'] = [];
  for (const [ck, agg] of csvClassAgg) {
    if (activeClassByKey.has(ck)) continue;
    // Modal year level across the class's rows.
    let modal: string | null = null;
    let modalCount = 0;
    for (const [yl, count] of agg.yearLevels) {
      if (count > modalCount) { modal = yl; modalCount = count; }
    }
    toCreate.push({
      name: agg.name,
      yearLevel: modal,
      rowCount: agg.rowCount,
      yearLevelConflict: agg.yearLevels.size > 1,
    });
    const inactive = inactiveClassByKey.get(ck);
    if (inactive) inactiveNameClash.push({ name: agg.name, inactiveClassId: inactive.docId });
  }

  // Per active class: current active members, and whether any CSV row targets it.
  const membersByClass = new Map<string, ExistingStudent[]>();
  for (const s of students) {
    if (!s.isActive || !s.classId) continue;
    const list = membersByClass.get(s.classId) ?? [];
    list.push(s);
    membersByClass.set(s.classId, list);
  }
  const targetedClassIds = new Set<string>();
  for (const row of rows) {
    if (row.bucket === 'error') continue;
    const target = activeClassByKey.get(classKey(row.csv.className));
    if (target) targetedClassIds.add(target.docId);
  }

  const emptyAfterImport: ClassAnalysis['emptyAfterImport'] = [];
  const wholeClassMissing: ClassAnalysis['wholeClassMissing'] = [];
  for (const c of classes) {
    if (!c.isActive) continue;
    const members = membersByClass.get(c.docId) ?? [];
    if (members.length === 0) continue;
    const allMissing = members.every((m) => missingSet.has(m.docId));
    if (allMissing) {
      wholeClassMissing.push({ docId: c.docId, name: c.name, memberCount: members.length });
    }
    if (targetedClassIds.has(c.docId)) continue;
    // Nobody lands here; empty iff every member leaves (moves away or missing).
    const allLeave = members.every((m) => {
      if (missingSet.has(m.docId)) return true;
      const rowIdx = claimed.get(m.docId);
      if (rowIdx == null) return false;
      const row = rows[rowIdx - 1];
      const target = activeClassByKey.get(classKey(row.csv.className));
      return target?.docId !== c.docId;
    });
    if (allLeave) {
      emptyAfterImport.push({ docId: c.docId, name: c.name, memberCount: members.length });
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  const stats = {
    match: rows.filter((r) => r.bucket === 'match').length,
    matchArchived: rows.filter((r) => r.bucket === 'match_archived').length,
    nameSuggest: rows.filter((r) => r.bucket === 'name_suggest').length,
    new: rows.filter((r) => r.bucket === 'new').length,
    error: rows.filter((r) => r.bucket === 'error').length,
    missingGraduating: missing.filter((m) => m.disposition === 'graduating').length,
    missingLeaver: missing.filter((m) => m.disposition === 'leaver').length,
    idlessRows: rows.filter((r) => r.bucket !== 'error' && !idKey(r.csv.studentId)).length,
    activeStudentCount: students.filter((s) => s.isActive).length,
  };

  return {
    rows,
    missing,
    classes: { toCreate, emptyAfterImport, wholeClassMissing, inactiveNameClash },
    stats,
  };
}

/** Shared annotations for match / match_archived rows. */
function annotateMatch(
  out: ClassifiedRow,
  s: ExistingStudent,
  csv: RolloverCSVRow,
  csvYear: string | null,
  classById: Map<string, ExistingClass>,
  effectiveYearLevel: (s: ExistingStudent) => string | null
): void {
  const targetKey = classKey(csv.className);
  const currentClass = s.classId ? classById.get(s.classId) : undefined;
  if (!currentClass || classKey(currentClass.name) !== targetKey) {
    out.classChanged = {
      fromClassId: s.classId,
      fromClassName: currentClass?.name ?? null,
      toClassName: csv.className.trim(),
    };
  }

  if (csvYear) {
    const from = effectiveYearLevel(s);
    const fromNorm = from && isLadderYearLevel(from) ? normalizeYearLevel(from) : from;
    const toNorm = isLadderYearLevel(csvYear) ? normalizeYearLevel(csvYear) : csvYear;
    if (fromNorm !== toNorm) {
      out.yearLevelChanged = { from, to: csvYear };
    }
    // Off-pattern: we expected the simple ladder bump (repeats, skips and
    // corrections are trusted — the SIS is the source of truth — but flagged).
    const expected = nextYearLevel(from);
    if (expected.changed && expected.next !== toNorm) {
      out.offLadder = true;
      out.warnings.push(`Year level ${from} → ${csvYear} isn't the usual next step (${expected.next})`);
    }
  }

  const storedName = `${s.firstName} ${s.lastName}`.trim();
  if (fullNameKey(csv.firstName, csv.lastName) !== fullNameKey(s.firstName, s.lastName)) {
    out.nameMismatch = { storedName };
    out.warnings.push(`Name differs from the existing record ("${storedName}") — the CSV name will be applied`);
  }
}
