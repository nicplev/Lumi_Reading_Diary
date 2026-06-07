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
 * tolerating up to `maxRestDays` total missed days before the streak ends. A
 * tolerated gap does NOT add to the count — so 5 reads with one gap in the
 * middle yields a streak of 5 spanning 6 calendar days.
 *
 * The streak is only "live" if the most recent reading day is today or
 * yesterday; otherwise it is 0 (mirrors the app's active-streak gate). Unread
 * days at the leading edge (e.g. today, before tonight's log) never burn a rest
 * day.
 *
 * @param {Set<string>} readingDates Local "YYYY-MM-DD" days the student read.
 * @param {string} today Today's local date as "YYYY-MM-DD".
 * @param {number} maxRestDays Max missed days the streak can bridge.
 * @return {{currentStreak: number, restDaysRemaining: number}} The live streak
 *   and how many rest days remain (maxRestDays minus gaps bridged within it).
 */
export function computeGentleStreak(
  readingDates: Set<string>,
  today: string,
  maxRestDays: number = MAX_REST_DAYS,
): {currentStreak: number; restDaysRemaining: number} {
  if (readingDates.size === 0) {
    return {currentStreak: 0, restDaysRemaining: maxRestDays};
  }

  // Not live unless the student read today or yesterday.
  if (!readingDates.has(today) && !readingDates.has(shiftDays(today, -1))) {
    return {currentStreak: 0, restDaysRemaining: maxRestDays};
  }

  const earliest = [...readingDates].sort()[0];

  let streak = 0;
  let bridgedGaps = 0; // missed days confirmed to sit *between* counted reads
  let pendingMisses = 0; // missed days since the last counted read
  let cursor = today;

  while (cursor >= earliest) {
    if (readingDates.has(cursor)) {
      // Can we bridge the run of misses back to this read?
      if (bridgedGaps + pendingMisses > maxRestDays) break;
      streak++;
      bridgedGaps += pendingMisses;
      pendingMisses = 0;
    } else if (streak > 0) {
      // Only count gaps once the streak has actually started.
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
