// Pure year-ladder logic (no Firestore imports) shared by lib/access.ts and
// the rollover import classifier — the classifier is unit-tested outside Next,
// so it must not transitively pull in firebase-admin. Mirrors
// functions/src/access.ts; keep the two in sync.

export const YEAR_LADDER = ['Prep', '1', '2', '3', '4', '5', '6'];
export const PREP_SYNONYMS = ['prep', 'foundation', 'kindergarten', 'kinder', 'k', 'f'];

/** "Year 4" / "Yr4" / "Y 4" / "Grade 4" / "Gr.4" → the bare rung. */
const YEAR_WORD_PREFIX = /^(?:year|yr|grade|gr|y)[\s._-]*/i;

/** A whole number, optionally zero-padded and/or with a zero decimal tail. */
const NUMERIC_LEVEL = /^(\d+)(?:\.0+)?$/;

/**
 * Normalise a year-level label onto the ladder: Prep synonyms → 'Prep',
 * trimmed otherwise. Returns the input verbatim (trimmed) when it isn't a
 * recognised rung — callers decide whether unknown values are acceptable.
 *
 * SIS exports are the reason this does more than a synonym lookup. CASES21
 * emits `ROUND(SCHOOL_YEAR,0)`, which renders as `0.0`…`6.0`, and its
 * Foundation year is **0** — so a raw export carries no ladder rung at all
 * unless we decode the numeric form. Zero-padding (`04`) and worded labels
 * (`Year 4`) show up in hand-made and other-vendor files.
 */
export function normalizeYearLevel(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed === '') return trimmed;
  if (PREP_SYNONYMS.includes(trimmed.toLowerCase())) return 'Prep';

  const bare = trimmed.replace(YEAR_WORD_PREFIX, '').trim();
  if (bare !== trimmed && PREP_SYNONYMS.includes(bare.toLowerCase())) return 'Prep';

  const numeric = NUMERIC_LEVEL.exec(bare);
  if (numeric) {
    const value = Number(numeric[1]);
    // CASES21/Victorian convention: year 0 is Foundation (Prep).
    return value === 0 ? 'Prep' : String(value);
  }

  return trimmed;
}

/** Whether a (raw) year-level label sits on the ladder at all. */
export function isLadderYearLevel(raw: string | null | undefined): boolean {
  if (raw == null || raw.trim() === '') return false;
  return YEAR_LADDER.includes(normalizeYearLevel(raw));
}

/** Advance a recognised year level; flag graduates past the top. */
export function nextYearLevel(current: string | null | undefined): {
  next: string | null;
  graduated: boolean;
  changed: boolean;
} {
  if (current == null || current === '') {
    return { next: current ?? null, graduated: false, changed: false };
  }
  const normalised = normalizeYearLevel(current);
  const idx = YEAR_LADDER.indexOf(normalised);
  if (idx === -1) return { next: current, graduated: false, changed: false };
  if (idx === YEAR_LADDER.length - 1) {
    return { next: normalised, graduated: true, changed: false };
  }
  return { next: YEAR_LADDER[idx + 1], graduated: false, changed: true };
}

/**
 * Ladder decision for renewals, honouring the rollover import's authority
 * marker. When the import wrote a student's year level it also stamps
 * `additionalInfo.yearLevelSetForYear` with the target academic year; a
 * renewal into that year (or earlier) must NOT bump the level again — the
 * double-bump would silently skip the student a grade. `>=` keeps a late or
 * repeated renewal click safe too. Schools that don't use the import never
 * carry the marker, so the existing bump behaviour is unchanged.
 */
export function yearLevelForRenewal(
  currentYearLevel: string | null | undefined,
  yearLevelSetForYear: unknown,
  targetAcademicYear: number
): { next: string | null; graduated: boolean; changed: boolean; setByImport: boolean } {
  if (typeof yearLevelSetForYear === 'number' && yearLevelSetForYear >= targetAcademicYear) {
    return {
      next: currentYearLevel ?? null,
      // Still flag top-of-ladder students as graduating — the import set the
      // level, but the renewal roster must keep de-selecting graduates.
      graduated: nextYearLevel(currentYearLevel).graduated,
      changed: false,
      setByImport: true,
    };
  }
  return { ...nextYearLevel(currentYearLevel), setByImport: false };
}
