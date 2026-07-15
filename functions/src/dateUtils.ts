/**
 * Pure date & streak math for student-stats aggregation.
 *
 * These helpers are deliberately free of any Firebase dependency so they can be
 * unit-tested in isolation (see functions/test/dateUtils.test.js). Every "day"
 * is computed in the school's local timezone to avoid the UTC-boundary
 * off-by-one errors that plagued the old aggregation (a 23:30 local log used to
 * land on the next UTC day).
 *
 * Design philosophy: progress is monotonic. The "gentle streak" tolerates
 * missed nights instead of resetting to zero, and is a pure function of the set
 * of local reading-date strings — so re-running aggregation is idempotent.
 */

/** Max missed days a gentle streak can bridge before it ends. */
export const MAX_REST_DAYS = 2;

/** Hard cap on backward day-walks so malformed data can never loop long. */
const WALK_CAP_DAYS = 400;

/** A school-term date range, inclusive local "YYYY-MM-DD" strings. */
export interface TermRange {
  start: string;
  end: string;
}

const TERM_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Coerce a term-date value (Firestore Timestamp, JS Date, or ISO string) to
 * the calendar date it was entered as. The portal's date-only inputs are
 * stored as UTC midnight (`new Date("YYYY-MM-DD")`), so the UTC date string
 * is the exact day the admin picked.
 * @param {unknown} v The raw value from the school document.
 * @return {string | null} "YYYY-MM-DD", or null if unparseable.
 */
export function coerceTermDateStr(v: unknown): string | null {
  if (typeof v === "string") {
    const m = v.match(/^\d{4}-\d{2}-\d{2}/);
    return m ? m[0] : null;
  }
  const maybe = v as {toDate?: () => Date} | Date | null | undefined;
  const d =
    maybe instanceof Date ? maybe :
      typeof maybe?.toDate === "function" ? maybe.toDate() : null;
  if (!(d instanceof Date) || isNaN(d.getTime())) return null;
  return d.toISOString().split("T")[0];
}

/**
 * Defensively parse a school doc's `termDates` field. Two shapes are
 * accepted, and anything malformed is silently dropped so bad data can never
 * break streaks:
 *  - The portal settings shape (what schools actually have):
 *    `{term1Start, term1End, term2Start, ...}` with Timestamp/Date/ISO values.
 *  - An array of `{start, end}` "YYYY-MM-DD" ranges.
 * Ranges with start > end are dropped.
 * @param {unknown} raw The raw `termDates` field from the school document.
 * @return {TermRange[]} The valid term ranges (possibly empty).
 */
export function parseTermDates(raw: unknown): TermRange[] {
  const out: TermRange[] = [];

  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (typeof item !== "object" || item === null) continue;
      const rec = item as Record<string, unknown>;
      const start = rec.start;
      const end = rec.end;
      if (typeof start !== "string" || typeof end !== "string") continue;
      if (!TERM_DATE_RE.test(start) || !TERM_DATE_RE.test(end)) continue;
      if (start > end) continue;
      out.push({start, end});
    }
    return out;
  }

  if (typeof raw === "object" && raw !== null) {
    const rec = raw as Record<string, unknown>;
    for (const key of Object.keys(rec)) {
      const m = key.match(/^term(\d+)Start$/);
      if (!m) continue;
      const start = coerceTermDateStr(rec[key]);
      const end = coerceTermDateStr(rec[`term${m[1]}End`]);
      if (!start || !end || start > end) continue;
      out.push({start, end});
    }
    out.sort((a, b) => (a.start < b.start ? -1 : a.start > b.start ? 1 : 0));
  }

  return out;
}

/**
 * Predicate for "does this local day count toward streak gaps?". Days inside
 * any term range count; days outside every range (school holidays) are free —
 * they never burn rest days and never break a streak, though reading on them
 * still extends the streak. No/empty term dates ⇒ every day counts (the
 * behaviour before term dates existed).
 * @param {TermRange[]} termDates Valid term ranges (see parseTermDates).
 * @return {function(string): boolean} The counting-day predicate.
 */
export function buildIsCountingDay(
  termDates: TermRange[],
): (dateStr: string) => boolean {
  if (termDates.length === 0) return () => true;
  return (dateStr) =>
    termDates.some((t) => dateStr >= t.start && dateStr <= t.end);
}

/**
 * Format a Date as "YYYY-MM-DD" in the given IANA timezone.
 * Falls back to the UTC date if the timezone is invalid (mirrors getLocalTime).
 * @param {Date} d The instant to format.
 * @param {string} tz The IANA timezone string (e.g. "Europe/London").
 * @return {string} The local calendar date as "YYYY-MM-DD".
 */
export function localDateString(d: Date, tz: string): string {
  try {
    // en-CA renders ISO-style YYYY-MM-DD.
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(d);
  } catch {
    return d.toISOString().split("T")[0];
  }
}

/**
 * Offset from UTC for an instant in an IANA timezone. Invalid timezones fall
 * back to UTC, matching localDateString's failure posture.
 * @param {Date} d The instant at which to resolve the offset.
 * @param {string} tz The IANA timezone.
 * @return {number} Local wall-clock minus UTC, in milliseconds.
 */
function timezoneOffsetMs(d: Date, tz: string): number {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(d);
    const values: Record<string, number> = {};
    for (const part of parts) {
      if (part.type !== "literal") values[part.type] = Number(part.value);
    }
    const wallClockAsUtc = Date.UTC(
      values.year,
      values.month - 1,
      values.day,
      values.hour,
      values.minute,
      values.second,
    );
    return wallClockAsUtc - d.getTime();
  } catch {
    return 0;
  }
}

/**
 * Convert a local calendar midnight into its UTC instant. Resolving the
 * offset twice handles dates where the offset at naive UTC midnight differs
 * from the offset at local midnight because of a nearby DST transition.
 * @param {string} dateStr Local date as YYYY-MM-DD.
 * @param {string} tz The school's IANA timezone.
 * @return {Date} UTC instant corresponding to local midnight.
 */
function localMidnightUtc(dateStr: string, tz: string): Date {
  if (!TERM_DATE_RE.test(dateStr)) {
    throw new RangeError(`Invalid local date: ${dateStr}`);
  }
  const naiveUtc = new Date(`${dateStr}T00:00:00.000Z`);
  if (naiveUtc.toISOString().slice(0, 10) !== dateStr) {
    throw new RangeError(`Invalid local date: ${dateStr}`);
  }
  let offset = timezoneOffsetMs(naiveUtc, tz);
  let result = new Date(naiveUtc.getTime() - offset);
  offset = timezoneOffsetMs(result, tz);
  result = new Date(naiveUtc.getTime() - offset);
  return result;
}

/**
 * UTC query bounds for one school-local calendar day. The end is exclusive,
 * so adjacent dates cannot overlap. Computing both midnights independently
 * correctly yields 23- and 25-hour ranges across daylight-saving changes.
 * @param {string} dateStr Local date as YYYY-MM-DD.
 * @param {string} tz The school's IANA timezone.
 * @return {{startInclusive: Date, endExclusive: Date}} UTC range.
 */
export function localDateUtcRange(
  dateStr: string,
  tz: string,
): {startInclusive: Date; endExclusive: Date} {
  return {
    startInclusive: localMidnightUtc(dateStr, tz),
    endExclusive: localMidnightUtc(shiftDays(dateStr, 1), tz),
  };
}

/**
 * Add `delta` days to a "YYYY-MM-DD" string, returning a "YYYY-MM-DD".
 * Anchored at noon UTC so DST transitions can never shift the calendar day
 * (we only need day granularity here).
 * @param {string} dateStr The base date as "YYYY-MM-DD".
 * @param {number} delta The number of days to add (may be negative).
 * @return {string} The shifted date as "YYYY-MM-DD".
 */
export function shiftDays(dateStr: string, delta: number): string {
  const base = new Date(`${dateStr}T12:00:00Z`);
  base.setUTCDate(base.getUTCDate() + delta);
  return base.toISOString().split("T")[0];
}

/**
 * Integer day-number for a "YYYY-MM-DD" string (days since the epoch).
 * @param {string} dateStr The date as "YYYY-MM-DD".
 * @return {number} The number of whole days since the Unix epoch.
 */
function dayNumber(dateStr: string): number {
  return Math.floor(new Date(`${dateStr}T12:00:00Z`).getTime() / 86400000);
}

/**
 * Stateless, forgiving "gentle streak".
 *
 * Walks backward from `today` over the set of local reading-date strings,
 * tolerating up to `maxRestDays` total missed *counting* days before the
 * streak ends. A tolerated gap does NOT add to the count — so 5 reads with
 * one gap in the middle yields a streak of 5 spanning 6 calendar days.
 *
 * `isCountingDay` (default: every day counts) marks school-holiday days as
 * non-counting: they never burn rest days and never break a streak, but a
 * read ON a holiday day still extends the streak — holiday reading is
 * rewarded, never required.
 *
 * The streak is "live" exactly while it is still continuable: the counting-day
 * gap since the last read (up to and including today) must be ≤
 * maxRestDays + 1, i.e. reading tonight would still bridge it. (This replaces
 * the old "read today or yesterday" gate, which zeroed a Friday-reader's
 * streak on Sunday even though Monday's log would have continued it.) Unread
 * days at the leading edge never burn a rest day.
 *
 * @param {Set<string>} readingDates Local "YYYY-MM-DD" days the student read.
 * @param {string} today Today's local date as "YYYY-MM-DD".
 * @param {number} maxRestDays Max missed counting days the streak can bridge.
 * @param {function(string): boolean} isCountingDay Whether a local day
 *   counts toward gaps (see buildIsCountingDay). Defaults to always-true.
 * @return {{currentStreak: number, restDaysRemaining: number}} The live streak
 *   and how many rest days remain (maxRestDays minus gaps bridged within it).
 */
export function computeGentleStreak(
  readingDates: Set<string>,
  today: string,
  maxRestDays: number = MAX_REST_DAYS,
  isCountingDay: (dateStr: string) => boolean = () => true,
): {currentStreak: number; restDaysRemaining: number} {
  if (readingDates.size === 0) {
    return {currentStreak: 0, restDaysRemaining: maxRestDays};
  }

  // Most recent reading day on or before today (future-dated logs are
  // ignored — the walk below starts at today).
  let lastRead: string | null = null;
  for (const d of readingDates) {
    if (d <= today && (lastRead === null || d > lastRead)) lastRead = d;
  }
  if (lastRead === null) {
    return {currentStreak: 0, restDaysRemaining: maxRestDays};
  }

  // Liveness: the gap of counting days after lastRead, up to and including
  // today, must still be bridgeable by reading tonight.
  let gap = 0;
  let walked = 0;
  let cursor = today;
  while (cursor > lastRead) {
    if (isCountingDay(cursor)) gap++;
    if (gap > maxRestDays + 1 || ++walked > WALK_CAP_DAYS) {
      return {currentStreak: 0, restDaysRemaining: maxRestDays};
    }
    cursor = shiftDays(cursor, -1);
  }

  const earliest = [...readingDates].sort()[0];

  let streak = 0;
  let bridgedGaps = 0; // missed counting days sitting *between* counted reads
  let pendingMisses = 0; // missed counting days since the last counted read
  cursor = today;

  while (cursor >= earliest) {
    if (readingDates.has(cursor)) {
      // Can we bridge the run of misses back to this read?
      if (bridgedGaps + pendingMisses > maxRestDays) break;
      streak++;
      bridgedGaps += pendingMisses;
      pendingMisses = 0;
    } else if (streak > 0 && isCountingDay(cursor)) {
      // Only counting (in-term) misses spend the budget, and only once the
      // streak has actually started — leading-edge unread days are free.
      pendingMisses++;
      // Budget blown — no earlier read could attach, so stop early.
      if (bridgedGaps + pendingMisses > maxRestDays) break;
    }
    cursor = shiftDays(cursor, -1);
  }

  return {
    currentStreak: streak,
    restDaysRemaining: Math.max(0, maxRestDays - bridgedGaps),
  };
}

/**
 * Longest gentle streak ever achieved, using the same ≤maxRestDays tolerance.
 * Implemented as a sliding window over the sorted unique days: a window is valid
 * while the missed days within it (span minus reads) stays within budget.
 *
 * Deliberately holiday-blind (no isCountingDay): being conservative across
 * term breaks is fine because longestStreak is monotonic — callers guard it
 * with max(prior, longest, currentStreak), and a live cross-holiday
 * currentStreak feeds that max while it is running.
 * @param {Set<string>} readingDates Local "YYYY-MM-DD" days the student read.
 * @param {number} maxRestDays Max missed days a run can bridge.
 * @return {number} The longest tolerant run of reading days.
 */
export function computeLongestStreak(
  readingDates: Set<string>,
  maxRestDays: number = MAX_REST_DAYS,
): number {
  const days = [...readingDates].sort().map(dayNumber);
  if (days.length === 0) return 0;

  let longest = 1;
  let i = 0;
  for (let j = 0; j < days.length; j++) {
    // Shrink from the left until the missed days within [i, j] fit the budget.
    while (days[j] - days[i] - (j - i) > maxRestDays) i++;
    longest = Math.max(longest, j - i + 1);
  }
  return longest;
}

/**
 * Count distinct reading days within the rolling window ending today.
 * e.g. windowDays=30 counts reads in [today-29, today] inclusive.
 * @param {Set<string>} readingDates Local "YYYY-MM-DD" days the student read.
 * @param {string} today Today's local date as "YYYY-MM-DD".
 * @param {number} windowDays The size of the rolling window.
 * @return {number} The count of distinct reading days in the window.
 */
export function countInWindow(
  readingDates: Set<string>,
  today: string,
  windowDays: number,
): number {
  const start = shiftDays(today, -(windowDays - 1));
  let count = 0;
  for (const d of readingDates) {
    // Lexicographic comparison is valid for zero-padded YYYY-MM-DD.
    if (d >= start && d <= today) count++;
  }
  return count;
}
