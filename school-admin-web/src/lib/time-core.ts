/**
 * Pure school-timezone date math — no Firebase imports, so it can be unit-run
 * directly with Node. `school-time.ts` re-exports everything here and adds the
 * Firestore-backed timezone lookup; import from there in server code.
 *
 * Why this exists: the portal runs on Cloud Run outside Australia, so
 * `new Date()` + `setHours(0,0,0,0)` produces the SERVER's midnight, not the
 * school's. Every "today" / "this week" / period boundary must be computed in
 * the school's IANA timezone via these helpers.
 *
 * Intl.DateTimeFormat construction is expensive (~0.1-1ms) while formatting is
 * cheap, and these helpers run per-log over year-long scans — so formatters
 * are memoized per timezone.
 */

export const DEFAULT_TIMEZONE = 'Australia/Sydney';

// ─── Memoized formatters ─────────────────────────────────────────────────────

const dateFormatters = new Map<string, Intl.DateTimeFormat | null>();
const weekdayFormatters = new Map<string, Intl.DateTimeFormat | null>();
const offsetFormatters = new Map<string, Intl.DateTimeFormat | null>();

function getFormatter(
  cache: Map<string, Intl.DateTimeFormat | null>,
  tz: string,
  build: () => Intl.DateTimeFormat,
): Intl.DateTimeFormat | null {
  if (cache.has(tz)) return cache.get(tz)!;
  let fmt: Intl.DateTimeFormat | null;
  try {
    fmt = build();
  } catch {
    fmt = null; // Invalid tz — remembered so we don't rethrow per call.
  }
  cache.set(tz, fmt);
  return fmt;
}

// ─── Local date strings ──────────────────────────────────────────────────────

/** Format an instant as "YYYY-MM-DD" in the given timezone (UTC on bad tz). */
export function localDateString(d: Date, tz: string): string {
  const fmt = getFormatter(dateFormatters, tz, () =>
    new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }),
  );
  return fmt ? fmt.format(d) : d.toISOString().split('T')[0];
}

/** Add days to a "YYYY-MM-DD" string (noon-UTC anchored, DST-proof). */
export function shiftDateStr(dateStr: string, delta: number): string {
  const base = new Date(`${dateStr}T12:00:00Z`);
  base.setUTCDate(base.getUTCDate() + delta);
  return base.toISOString().split('T')[0];
}

/** Whole calendar days from `fromStr` to `toStr` (positive when to > from). */
export function calendarDaysBetween(fromStr: string, toStr: string): number {
  const from = Date.parse(`${fromStr}T12:00:00Z`);
  const to = Date.parse(`${toStr}T12:00:00Z`);
  return Math.round((to - from) / 86400000);
}

// ─── Zoned instants ──────────────────────────────────────────────────────────

function tzOffsetMs(instant: Date, tz: string): number | null {
  const fmt = getFormatter(offsetFormatters, tz, () =>
    new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }),
  );
  if (!fmt) return null;
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(instant)) parts[p.type] = p.value;
  const asUtc = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    // Some ICU versions render midnight as "24".
    parts.hour === '24' ? 0 : Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  return asUtc - instant.getTime();
}

/**
 * The instant at which a "YYYY-MM-DD" local day starts in `tz` (local
 * midnight as a UTC Date, two-pass DST correction). Falls back to UTC
 * midnight on a bad timezone.
 */
export function zonedDayStart(dateStr: string, tz: string): Date {
  const guess = new Date(`${dateStr}T00:00:00Z`);
  const offset = tzOffsetMs(guess, tz);
  if (offset === null) return guess;
  let result = new Date(guess.getTime() - offset);
  const offset2 = tzOffsetMs(result, tz);
  if (offset2 !== null && offset2 !== offset) {
    result = new Date(guess.getTime() - offset2);
  }
  return result;
}

/** The last instant of a "YYYY-MM-DD" local day (23:59:59.999 local). */
export function zonedDayEnd(dateStr: string, tz: string): Date {
  return new Date(zonedDayStart(shiftDateStr(dateStr, 1), tz).getTime() - 1);
}

/** The instant the school-local day containing `now` started. */
export function startOfLocalDay(now: Date, tz: string): Date {
  return zonedDayStart(localDateString(now, tz), tz);
}

// ─── Weekdays ────────────────────────────────────────────────────────────────

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/** Weekday index of an instant in `tz`: Mon=0 … Sun=6 (UTC on bad tz). */
export function localWeekdayIndex(d: Date, tz: string): number {
  const fmt = getFormatter(weekdayFormatters, tz, () =>
    new Intl.DateTimeFormat('en-US', { timeZone: tz, weekday: 'short' }),
  );
  const name = fmt
    ? fmt.format(d)
    : new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short' }).format(d);
  const idx = WEEKDAYS.indexOf(name);
  return idx === -1 ? 0 : idx;
}

/**
 * Whether a "YYYY-MM-DD" calendar date is a Saturday/Sunday. A date string's
 * weekday is absolute — no timezone needed (noon-UTC anchor avoids any
 * boundary ambiguity).
 */
export function isWeekendDateStr(dateStr: string): boolean {
  const dow = new Date(`${dateStr}T12:00:00Z`).getUTCDay(); // 0=Sun … 6=Sat
  return dow === 0 || dow === 6;
}

/** The instant the school-local Monday-anchored week containing `now` started. */
export function startOfLocalWeek(now: Date, tz: string): Date {
  const todayStr = localDateString(now, tz);
  const mondayStr = shiftDateStr(todayStr, -localWeekdayIndex(now, tz));
  return zonedDayStart(mondayStr, tz);
}
