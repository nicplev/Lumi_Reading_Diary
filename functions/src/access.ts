/**
 * Access-model core: academic-year boundary math and the canonical shapes for
 * the materialised `student.access` and `school.access` maps.
 *
 * The date helpers are deliberately free of any Firebase dependency so they can
 * be unit-tested in isolation (see functions/test/access.test.js), mirroring
 * dateUtils.ts. Builders return plain objects carrying JS `Date`s — the Admin
 * SDK stores a `Date` as a Firestore Timestamp transparently, so callers write
 * them directly.
 *
 * The single source of truth for the live year is `config/academicYear`
 * (currentAcademicYear). These helpers compute the *boundary instants* a given
 * year implies, and a sensible default year for backfill when no config exists.
 */

export const DEFAULT_TIMEZONE = "Australia/Sydney";

export type StudentAccessStatus = "active" | "expired" | "suspended" | "revoked";
export type StudentAccessSource =
  | "school_renewal"
  | "book_pack_assumed"
  | "parent_direct"
  | "comp";

export interface StudentAccess {
  status: StudentAccessStatus;
  academicYear: number;
  expiresAt: Date;
  source?: StudentAccessSource;
  grantedAt?: Date;
  grantedBy?: string;
}

export type SchoolAccessStatus = "active" | "suspended";

export interface SchoolAccess {
  status: SchoolAccessStatus;
  academicYear: number;
  reason?: string;
  updatedAt?: Date;
}

export type SubscriptionStatus =
  | "paid"
  | "unpaid"
  | "comp"
  | "trial"
  | "grace"
  | "cancelled";

const ACTIVE_SUBSCRIPTION_STATUSES: readonly SubscriptionStatus[] = [
  "paid",
  "comp",
  "trial",
  "grace",
];

/**
 * Whether a subscription status grants the school active access for the year.
 * @param {string|null|undefined} status The subscription status.
 * @return {boolean} True if the status is one of paid/comp/trial/grace.
 */
export function isActiveSubscriptionStatus(
  status: string | null | undefined,
): boolean {
  return (
    status != null &&
    (ACTIVE_SUBSCRIPTION_STATUSES as readonly string[]).includes(status)
  );
}

/**
 * Year-number portion ("YYYY") of a Date in the given IANA timezone.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone.
 * @return {number} The local calendar year.
 */
function localYear(d: Date, tz: string): number {
  try {
    return Number(
      new Intl.DateTimeFormat("en-CA", {
        timeZone: tz,
        year: "numeric",
      }).format(d),
    );
  } catch {
    return d.getUTCFullYear();
  }
}

/**
 * Month number (1-12) of a Date in the given IANA timezone.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone.
 * @return {number} The local month (1-12).
 */
function localMonth(d: Date, tz: string): number {
  try {
    return Number(
      new Intl.DateTimeFormat("en-CA", {timeZone: tz, month: "numeric"}).format(
        d,
      ),
    );
  } catch {
    return d.getUTCMonth() + 1;
  }
}

/**
 * Day-of-month of a Date in the given IANA timezone.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone.
 * @return {number} The local day-of-month.
 */
function localDay(d: Date, tz: string): number {
  try {
    return Number(
      new Intl.DateTimeFormat("en-CA", {timeZone: tz, day: "numeric"}).format(
        d,
      ),
    );
  } catch {
    return d.getUTCDate();
  }
}

/** The day-of-month the global rollover runs (~25 Jan). */
export const ROLLOVER_DAY = 25;

/**
 * The academic year (calendar year the AU school-year STARTS) that an instant
 * falls in. January days before the rollover still belong to the *previous*
 * year's cohort, which is mid-suspension until rollover advances the year.
 * After ~25 Jan the new year is in session.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone (defaults to Australia/Sydney).
 * @return {number} The academic year.
 */
export function academicYearForDate(
  d: Date,
  tz: string = DEFAULT_TIMEZONE,
): number {
  const year = localYear(d, tz);
  const month = localMonth(d, tz);
  const day = localDay(d, tz);
  // Jan 1 .. (rollover - 1) belongs to the prior year's cohort.
  if (month === 1 && day < ROLLOVER_DAY) return year - 1;
  return year;
}

/**
 * Absolute hard-expiry instant for a given academic year: end of January of the
 * following calendar year, local time. e.g. year 2026 → 2027-01-31T23:59:59
 * Australia/Sydney. Built as a UTC instant by subtracting the timezone offset.
 * @param {number} academicYear Calendar year the school-year starts.
 * @param {string} tz The IANA timezone (defaults to Australia/Sydney).
 * @return {Date} The hard-expiry instant.
 */
export function hardExpiryFor(
  academicYear: number,
  tz: string = DEFAULT_TIMEZONE,
): Date {
  const expiryYear = academicYear + 1;
  // Midnight-31-Jan wall-clock in tz, expressed as a UTC instant.
  const naiveUtc = Date.UTC(expiryYear, 0, 31, 23, 59, 59);
  const offsetMs = timezoneOffsetMs(new Date(naiveUtc), tz);
  return new Date(naiveUtc - offsetMs);
}

/**
 * Offset (ms) of a timezone from UTC at a given instant: localWallClock - UTC.
 * For Australia/Sydney in summer (AEDT) this is +11h.
 * @param {Date} d The instant.
 * @param {string} tz The IANA timezone.
 * @return {number} The offset in milliseconds.
 */
function timezoneOffsetMs(d: Date, tz: string): number {
  try {
    const dtf = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: false,
    });
    const parts = dtf.formatToParts(d);
    const map: Record<string, number> = {};
    for (const p of parts) {
      if (p.type !== "literal") map[p.type] = Number(p.value);
    }
    const asUtc = Date.UTC(
      map.year,
      map.month - 1,
      map.day,
      map.hour === 24 ? 0 : map.hour,
      map.minute,
      map.second,
    );
    return asUtc - d.getTime();
  } catch {
    return 0;
  }
}

/**
 * AU primary-school year ladder. Entry synonyms (Foundation/Kindergarten/K/F)
 * normalise to Prep. After the final year, the student has graduated.
 */
export const YEAR_LADDER = ["Prep", "1", "2", "3", "4", "5", "6"];

const PREP_SYNONYMS = ["prep", "foundation", "kindergarten", "kinder", "k", "f"];

/**
 * Advance a student's year level by one on renewal. Returns the next level and
 * whether the student has graduated past the top of the ladder. Unknown values
 * (or null) are left unchanged and never flagged as graduated — class/year
 * assignment stays manual in v1, so this only bumps a recognised label.
 * @param {string|null|undefined} current The student's current year level.
 * @return {!Object} Object carrying `next`, `graduated`, and `changed`.
 */
export function nextYearLevel(current: string | null | undefined): {
  next: string | null;
  graduated: boolean;
  changed: boolean;
} {
  if (current == null || current === "") {
    return {next: current ?? null, graduated: false, changed: false};
  }
  const normalised = PREP_SYNONYMS.includes(current.trim().toLowerCase()) ?
    "Prep" :
    current.trim();
  const idx = YEAR_LADDER.indexOf(normalised);
  if (idx === -1) {
    // Not a recognised ladder rung — leave untouched.
    return {next: current, graduated: false, changed: false};
  }
  if (idx === YEAR_LADDER.length - 1) {
    return {next: normalised, graduated: true, changed: false};
  }
  return {next: YEAR_LADDER[idx + 1], graduated: false, changed: true};
}

/**
 * Ladder decision for renewals, honouring the portal rollover import's
 * authority marker: when the import wrote a student's year level it stamps
 * `additionalInfo.yearLevelSetForYear` with the target academic year, and a
 * renewal into that year (or earlier) must NOT bump the level again — the
 * double-bump would silently skip the student a grade. `>=` keeps a late or
 * repeated renewal safe too. Mirrors yearLevelForRenewal in
 * school-admin-web/src/lib/access.ts — keep the two in sync.
 * @param {string|null|undefined} currentYearLevel The student's current level.
 * @param {unknown} yearLevelSetForYear `additionalInfo.yearLevelSetForYear`.
 * @param {number} targetAcademicYear The year being renewed into.
 * @return {!Object} Object carrying `next`, `graduated`, and `changed`.
 */
export function yearLevelForRenewal(
  currentYearLevel: string | null | undefined,
  yearLevelSetForYear: unknown,
  targetAcademicYear: number,
): {next: string | null; graduated: boolean; changed: boolean} {
  if (
    typeof yearLevelSetForYear === "number" &&
    yearLevelSetForYear >= targetAcademicYear
  ) {
    return {
      next: currentYearLevel ?? null,
      graduated: nextYearLevel(currentYearLevel).graduated,
      changed: false,
    };
  }
  return nextYearLevel(currentYearLevel);
}

/**
 * Build a fully-formed `student.access` map for the given academic year. Status
 * defaults to active; expiry is derived from the year unless overridden.
 * @param {object} params Grant parameters.
 * @return {StudentAccess} The materialised access map.
 */
export function buildStudentAccess(params: {
  academicYear: number;
  source: StudentAccessSource;
  grantedBy?: string;
  status?: StudentAccessStatus;
  now?: Date;
  tz?: string;
}): StudentAccess {
  const tz = params.tz ?? DEFAULT_TIMEZONE;
  const now = params.now ?? new Date();
  return {
    status: params.status ?? "active",
    academicYear: params.academicYear,
    expiresAt: hardExpiryFor(params.academicYear, tz),
    source: params.source,
    grantedAt: now,
    grantedBy: params.grantedBy,
  };
}

/**
 * Build a `school.access` map.
 * @param {object} params Status parameters.
 * @return {SchoolAccess} The materialised access map.
 */
export function buildSchoolAccess(params: {
  status: SchoolAccessStatus;
  academicYear: number;
  reason?: string;
  now?: Date;
}): SchoolAccess {
  return {
    status: params.status,
    academicYear: params.academicYear,
    reason: params.reason,
    updatedAt: params.now ?? new Date(),
  };
}
