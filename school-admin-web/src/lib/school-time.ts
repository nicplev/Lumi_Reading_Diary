/**
 * School-timezone day/week math for server-side queries.
 *
 * The portal runs on Cloud Run in a UTC/US region, so `new Date()` +
 * `setHours(0,0,0,0)` produces the SERVER's midnight, not the school's — an
 * Australian school's "today"/"this week" was starting up to ~14h late and
 * disagreeing with the app's streak engine (which buckets by school timezone,
 * defaulting to Australia/Sydney — see functions/src/dateUtils.ts). Every
 * dashboard/report boundary must go through these helpers instead.
 *
 * Weeks are Monday-anchored, matching the app and topReaderAward.
 */

import { adminDb } from '@/lib/firebase/admin';

export const DEFAULT_TIMEZONE = 'Australia/Sydney';

const tzCache = new Map<string, { tz: string; fetchedAt: number }>();
const TZ_CACHE_MS = 5 * 60 * 1000;

/** The school's IANA timezone, cached per server instance for 5 minutes. */
export async function getSchoolTimezone(schoolId: string): Promise<string> {
  const hit = tzCache.get(schoolId);
  if (hit && Date.now() - hit.fetchedAt < TZ_CACHE_MS) return hit.tz;
  let tz = DEFAULT_TIMEZONE;
  try {
    const snap = await adminDb.collection('schools').doc(schoolId).get();
    const raw = snap.data()?.timezone;
    if (typeof raw === 'string' && raw.length > 0) tz = raw;
  } catch {
    // Fall through to the default — a tz lookup must never break a dashboard.
  }
  tzCache.set(schoolId, { tz, fetchedAt: Date.now() });
  return tz;
}

/** Format an instant as "YYYY-MM-DD" in the given timezone (UTC on bad tz). */
export function localDateString(d: Date, tz: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(d);
  } catch {
    return d.toISOString().split('T')[0];
  }
}

/** Add days to a "YYYY-MM-DD" string (noon-UTC anchored, DST-proof). */
export function shiftDateStr(dateStr: string, delta: number): string {
  const base = new Date(`${dateStr}T12:00:00Z`);
  base.setUTCDate(base.getUTCDate() + delta);
  return base.toISOString().split('T')[0];
}

function tzOffsetMs(instant: Date, tz: string): number {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  });
  const parts: Record<string, string> = {};
  for (const p of dtf.formatToParts(instant)) parts[p.type] = p.value;
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
  try {
    const offset = tzOffsetMs(guess, tz);
    let result = new Date(guess.getTime() - offset);
    const offset2 = tzOffsetMs(result, tz);
    if (offset2 !== offset) result = new Date(guess.getTime() - offset2);
    return result;
  } catch {
    return guess;
  }
}

/** The instant the school-local day containing `now` started. */
export function startOfLocalDay(now: Date, tz: string): Date {
  return zonedDayStart(localDateString(now, tz), tz);
}

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/** Weekday index of an instant in `tz`: Mon=0 … Sun=6 (UTC on bad tz). */
export function localWeekdayIndex(d: Date, tz: string): number {
  let name: string;
  try {
    name = new Intl.DateTimeFormat('en-US', { timeZone: tz, weekday: 'short' }).format(d);
  } catch {
    name = new Intl.DateTimeFormat('en-US', { timeZone: 'UTC', weekday: 'short' }).format(d);
  }
  const idx = WEEKDAYS.indexOf(name);
  return idx === -1 ? 0 : idx;
}

/** The instant the school-local Monday-anchored week containing `now` started. */
export function startOfLocalWeek(now: Date, tz: string): Date {
  const todayStr = localDateString(now, tz);
  const mondayStr = shiftDateStr(todayStr, -localWeekdayIndex(now, tz));
  return zonedDayStart(mondayStr, tz);
}
