/**
 * Analytics period resolution — pure (no Firebase), unit-runnable with Node.
 *
 * Turns a UI period ('5days' | 'month' | 'term' | 'year') into concrete query
 * instants, computed in the SCHOOL's timezone. The old implementation used the
 * server clock for every boundary, which on a non-AU Cloud Run region started
 * an AU school's "month" ~10-14h late (or in the wrong month/year entirely at
 * boundaries) and treated term start/end days as beginning mid-morning.
 */

import {
  isWeekendDateStr,
  localDateString,
  shiftDateStr,
  zonedDayEnd,
  zonedDayStart,
  calendarDaysBetween,
} from './time-core';

export interface ResolvedPeriod {
  startDate: Date;
  endDate: Date;
  weekdaysOnly: boolean;
}

/**
 * Hard cap on a period's span. Term dates are free-form admin input — a
 * fat-fingered year (2062 for 2026) must not trigger a multi-year readingLogs
 * scan, which is exactly the class of timeout that used to surface as a
 * misleading "No data". A legitimate school year is ≤ ~370 days.
 */
const MAX_PERIOD_DAYS = 800;

/**
 * Recover the calendar date an admin picked from a stored term-date instant.
 * The portal writes date-only picks as UTC midnight (`new Date('YYYY-MM-DD')`),
 * so the UTC date string is the exact day chosen (mirrors
 * functions/src/dateUtils.ts coerceTermDateStr).
 */
function termCalendarDate(value: Date | undefined): string | null {
  if (!(value instanceof Date) || isNaN(value.getTime())) return null;
  return value.toISOString().split('T')[0];
}

/** Clamp an inclusive end instant to `now` (periods never extend into the future). */
function clampToNow(end: Date, now: Date): Date {
  return end > now ? now : end;
}

/** Enforce MAX_PERIOD_DAYS by pulling the start forward when needed. */
function capSpan(start: Date, end: Date, tz: string): Date {
  const startStr = localDateString(start, tz);
  const endStr = localDateString(end, tz);
  if (calendarDaysBetween(startStr, endStr) <= MAX_PERIOD_DAYS) return start;
  return zonedDayStart(shiftDateStr(endStr, -MAX_PERIOD_DAYS), tz);
}

export function resolvePeriod(
  period: string,
  termKey: string | null,
  termDates: Record<string, Date>,
  tz: string,
  now: Date = new Date(),
): ResolvedPeriod {
  const todayStr = localDateString(now, tz);

  if (period === '5days') {
    // The 5 school-local weekdays before today (existing product semantics:
    // the window runs from the 5th-last weekday through now, so today's logs
    // are included on top of the 5 full days).
    let cursor = todayStr;
    let weekdaysFound = 0;
    let guard = 0;
    while (weekdaysFound < 5 && guard < 14) {
      cursor = shiftDateStr(cursor, -1);
      if (!isWeekendDateStr(cursor)) weekdaysFound++;
      guard++;
    }
    return {
      startDate: zonedDayStart(cursor, tz),
      endDate: now,
      weekdaysOnly: true,
    };
  }

  if (period === 'month') {
    // First of the CURRENT month in school-local time — near month boundaries
    // the server's month can differ from the school's.
    const monthStartStr = `${todayStr.slice(0, 8)}01`;
    return {
      startDate: zonedDayStart(monthStartStr, tz),
      endDate: now,
      weekdaysOnly: true,
    };
  }

  if (period === 'term' && termKey) {
    const startStr = termCalendarDate(termDates[`${termKey}Start`]);
    if (startStr) {
      const endStr = termCalendarDate(termDates[`${termKey}End`]);
      // Inclusive of the whole local end day (the old code cut the term off
      // at UTC-midnight of the end date — mid-morning AEST).
      const end = endStr ? zonedDayEnd(endStr, tz) : now;
      const endDate = clampToNow(end, now);
      const startDate = zonedDayStart(startStr, tz);
      return {
        startDate: capSpan(startDate, endDate, tz),
        endDate,
        weekdaysOnly: false,
      };
    }
    // Unknown/unconfigured term — fall through to the year window rather than
    // crashing the whole analytics response on an undefined query bound.
  }

  // year — earliest term start to latest term end, else the school-local
  // calendar year to date.
  const startStrs = Object.entries(termDates)
    .filter(([k]) => k.endsWith('Start'))
    .map(([, v]) => termCalendarDate(v))
    .filter((s): s is string => s !== null)
    .sort();
  const endStrs = Object.entries(termDates)
    .filter(([k]) => k.endsWith('End'))
    .map(([, v]) => termCalendarDate(v))
    .filter((s): s is string => s !== null)
    .sort();

  const yearStart = startStrs.length > 0
    ? zonedDayStart(startStrs[0], tz)
    : zonedDayStart(`${todayStr.slice(0, 4)}-01-01`, tz);
  const yearEnd = endStrs.length > 0
    ? clampToNow(zonedDayEnd(endStrs[endStrs.length - 1], tz), now)
    : now;

  return {
    startDate: capSpan(yearStart, yearEnd, tz),
    endDate: yearEnd,
    weekdaysOnly: false,
  };
}
