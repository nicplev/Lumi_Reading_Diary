import { adminDb } from '@/lib/firebase/admin';
import {
  calendarDaysBetween,
  isWeekendDateStr,
  localDateString,
  shiftDateStr,
  startOfLocalDay,
} from '@/lib/time-core';

// --- Types ---

export interface ReadingMetrics {
  totalMinutes: number;
  totalBooks: number;
  totalLogs: number;
  completionRate: number;
  avgMinPerStudent: number;
  uniqueReaders: number;
}

export interface EngagementPoint {
  date: string;
  minutes: number;
  logs: number;
}

export interface ClassEngagementSeries {
  /** Classes with at least one log in the period, sorted by name. */
  classes: { id: string; name: string }[];
  /**
   * One entry per day in range (weekends skipped when weekdaysOnly). Each has
   * `date` (ISO yyyy-mm-dd) plus, per class, `${classId}:logs` and
   * `${classId}:minutes`. The client buckets these to weeks when the range is
   * long, mirroring the aggregate trend chart.
   */
  points: Array<Record<string, number | string>>;
}

export interface LevelBucket {
  level: string;
  count: number;
}

export interface ClassComparisonRow {
  classId: string;
  name: string;
  yearLevel?: string;
  studentCount: number;
  totalMinutes: number;
  totalLogs: number;
  booksRead: number;
  completionRate: number;
  avgMinPerStudent: number;
  readersToday: number;
}

export interface AtRiskStudent {
  id: string;
  name: string;
  classId: string;
  className: string;
  currentReadingLevel?: string;
  lastReadingDate: string | null;
  daysSinceRead: number;
  currentStreak: number;
}

export interface TopReader {
  id: string;
  name: string;
  className: string;
  totalMinutes: number;
  uniqueBooks: number;
  streak: number;
}

export interface PopularBook {
  title: string;
  count: number;
}

// --- Helpers ---
// Period resolution (server-clock-free) lives in '@/lib/analytics-period'.
// Every date below is bucketed in the SCHOOL's timezone: the tz parameter on
// each aggregator comes from the school doc (see the analytics API route).

/** School-local "YYYY-MM-DD" of a log's date, or null when the log has none. */
function logDayKey(d: FirebaseFirestore.DocumentData, tz: string): string | null {
  const ts: Date | undefined = d.date?.toDate?.();
  return ts ? localDateString(ts, tz) : null;
}

/**
 * Whether a log should be skipped under a weekdays-only period. Logs without
 * a date are kept (they can't be classified, and totals shouldn't lose them).
 */
function skipAsWeekend(
  weekdaysOnly: boolean,
  dayKey: string | null,
): boolean {
  return weekdaysOnly && dayKey !== null && isWeekendDateStr(dayKey);
}

/** Belt-and-braces bound on gap-fill loops (resolvePeriod already caps spans). */
const MAX_FILL_DAYS = 810;

// --- Query Functions ---

type LogDoc = FirebaseFirestore.QueryDocumentSnapshot<FirebaseFirestore.DocumentData>;

/**
 * Fetch a school's reading logs in [startDate, endDate] ONCE. The analytics
 * route used to run this identical scan 5× (metrics, trend, class comparison,
 * top readers, popular books); for a "year" period on a big school that meant
 * five full-year collection scans per page load → timeouts that surfaced as a
 * misleading "No data". The route now fetches once and passes the docs to each
 * aggregator (which still fall back to their own fetch when called standalone).
 */
export async function fetchReadingLogsInRange(
  schoolId: string,
  startDate: Date,
  endDate: Date,
): Promise<LogDoc[]> {
  const snap = await adminDb
    .collection('schools').doc(schoolId).collection('readingLogs')
    .where('date', '>=', startDate)
    .where('date', '<=', endDate)
    .get();
  return snap.docs;
}

export async function getReadingMetrics(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  prefetchedLogs?: LogDoc[],
): Promise<ReadingMetrics> {
  try {
    const logDocs = prefetchedLogs ?? (await fetchReadingLogsInRange(schoolId, startDate, endDate));

    let totalMinutes = 0;
    let totalBooks = 0;
    let completedCount = 0;
    let totalLogs = 0;
    const readers = new Set<string>();

    for (const doc of logDocs) {
      const d = doc.data();
      if (skipAsWeekend(weekdaysOnly, logDayKey(d, tz))) continue;
      totalMinutes += d.minutesRead ?? 0;
      if (Array.isArray(d.bookTitles)) totalBooks += d.bookTitles.length;
      if (d.status === 'completed') completedCount++;
      if (d.studentId) readers.add(d.studentId);
      totalLogs++;
    }

    const completionRate = totalLogs > 0 ? Math.round((completedCount / totalLogs) * 100) : 0;
    const schoolDoc = await adminDb.collection('schools').doc(schoolId).get();
    const studentCount = schoolDoc.data()?.studentCount ?? 1;
    const avgMinPerStudent = studentCount > 0 ? Math.round(totalMinutes / studentCount) : 0;

    return { totalMinutes, totalBooks, totalLogs, completionRate, avgMinPerStudent, uniqueReaders: readers.size };
  } catch {
    return { totalMinutes: 0, totalBooks: 0, totalLogs: 0, completionRate: 0, avgMinPerStudent: 0, uniqueReaders: 0 };
  }
}

export async function getEngagementTrend(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  prefetchedLogs?: LogDoc[],
): Promise<EngagementPoint[]> {
  try {
    const logDocs = prefetchedLogs ?? (await fetchReadingLogsInRange(schoolId, startDate, endDate));

    const byDate = new Map<string, { minutes: number; logs: number }>();

    for (const doc of logDocs) {
      const d = doc.data();
      const key = logDayKey(d, tz);
      if (key === null) continue; // undated logs can't sit on a date axis
      if (skipAsWeekend(weekdaysOnly, key)) continue;
      const existing = byDate.get(key) ?? { minutes: 0, logs: 0 };
      existing.minutes += d.minutesRead ?? 0;
      existing.logs += 1;
      byDate.set(key, existing);
    }

    // Fill in every school-local day in range (skipping weekends when
    // weekdaysOnly) so charts show explicit zero days. Iterating date STRINGS
    // keeps the fill keys aligned with the log keys above — iterating instants
    // and taking their UTC date drifted a day for tz east of UTC.
    const result: EngagementPoint[] = [];
    const endKey = localDateString(endDate, tz);
    let cursor = localDateString(startDate, tz);
    for (let i = 0; cursor <= endKey && i < MAX_FILL_DAYS; i++) {
      if (!weekdaysOnly || !isWeekendDateStr(cursor)) {
        const data = byDate.get(cursor) ?? { minutes: 0, logs: 0 };
        result.push({ date: cursor, ...data });
      }
      cursor = shiftDateStr(cursor, 1);
    }

    return result;
  } catch {
    return [];
  }
}

/**
 * Per-class engagement over the period — the multi-line "class comparison"
 * series (one line per class). Mirrors getEngagementTrend's daily bucketing and
 * gap-filling, but splits each day by classId. Reuses the prefetched logs, so
 * it adds no readingLogs scan (just one classes read to resolve names).
 */
export async function getClassEngagementTrend(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  prefetchedLogs?: LogDoc[],
): Promise<ClassEngagementSeries> {
  try {
    const logDocs = prefetchedLogs ?? (await fetchReadingLogsInRange(schoolId, startDate, endDate));

    // Aggregate per (dateKey → classId → totals).
    const byDate = new Map<string, Map<string, { logs: number; minutes: number }>>();
    const activeClassIds = new Set<string>();
    for (const doc of logDocs) {
      const d = doc.data();
      const classId = d.classId as string | undefined;
      if (!classId) continue;
      const key = logDayKey(d, tz);
      if (key === null) continue;
      if (skipAsWeekend(weekdaysOnly, key)) continue;
      activeClassIds.add(classId);
      let dayMap = byDate.get(key);
      if (!dayMap) { dayMap = new Map(); byDate.set(key, dayMap); }
      const cur = dayMap.get(classId) ?? { logs: 0, minutes: 0 };
      cur.logs += 1;
      cur.minutes += d.minutesRead ?? 0;
      dayMap.set(classId, cur);
    }

    if (activeClassIds.size === 0) return { classes: [], points: [] };

    // Resolve names for the classes that have activity.
    const classesSnap = await adminDb.collection('schools').doc(schoolId).collection('classes').get();
    const classNames = new Map<string, string>();
    classesSnap.docs.forEach((c) => {
      const data = c.data();
      classNames.set(c.id, (data.name as string) || (data.yearLevel as string) || 'Class');
    });
    const classes = Array.from(activeClassIds)
      .map((id) => ({ id, name: classNames.get(id) ?? 'Unknown class' }))
      .sort((a, b) => a.name.localeCompare(b.name));

    // Fill each school-local day in range (skipping weekends when
    // weekdaysOnly) — date-string iteration, matching getEngagementTrend.
    const points: Array<Record<string, number | string>> = [];
    const endKey = localDateString(endDate, tz);
    let cursor = localDateString(startDate, tz);
    for (let i = 0; cursor <= endKey && i < MAX_FILL_DAYS; i++) {
      if (!weekdaysOnly || !isWeekendDateStr(cursor)) {
        const dayMap = byDate.get(cursor);
        const point: Record<string, number | string> = { date: cursor };
        for (const c of classes) {
          const v = dayMap?.get(c.id);
          point[`${c.id}:logs`] = v?.logs ?? 0;
          point[`${c.id}:minutes`] = v?.minutes ?? 0;
        }
        points.push(point);
      }
      cursor = shiftDateStr(cursor, 1);
    }

    return { classes, points };
  } catch {
    return { classes: [], points: [] };
  }
}

export async function getLevelDistribution(schoolId: string, classId?: string): Promise<LevelBucket[]> {
  try {
    let query: FirebaseFirestore.Query = adminDb
      .collection('schools').doc(schoolId).collection('students')
      .where('isActive', '==', true);

    if (classId) {
      query = query.where('classId', '==', classId);
    }

    const snap = await query.get();
    const counts = new Map<string, number>();

    for (const doc of snap.docs) {
      const level = doc.data().currentReadingLevel ?? 'No Level';
      counts.set(level, (counts.get(level) ?? 0) + 1);
    }

    return Array.from(counts.entries())
      .map(([level, count]) => ({ level, count }))
      .sort((a, b) => b.count - a.count);
  } catch {
    return [];
  }
}

export async function getClassComparison(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  prefetchedLogs?: LogDoc[],
): Promise<ClassComparisonRow[]> {
  try {
    const classesSnap = await adminDb
      .collection('schools').doc(schoolId).collection('classes')
      .where('isActive', '==', true)
      .get();

    // "Read today" starts at the school-local midnight, not the server's.
    const today = startOfLocalDay(new Date(), tz);

    const logDocs = prefetchedLogs ?? (await fetchReadingLogsInRange(schoolId, startDate, endDate));

    const logsByClass = new Map<string, { minutes: number; bookTitles: Set<string>; completed: number; total: number; todayReaders: Set<string> }>();

    for (const doc of logDocs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date(0);
      if (skipAsWeekend(weekdaysOnly, logDayKey(d, tz))) continue;
      const cid = d.classId ?? '';
      const existing = logsByClass.get(cid) ?? { minutes: 0, bookTitles: new Set(), completed: 0, total: 0, todayReaders: new Set() };
      existing.minutes += d.minutesRead ?? 0;
      if (Array.isArray(d.bookTitles)) {
        for (const title of d.bookTitles) {
          if (typeof title === 'string' && title.trim()) {
            existing.bookTitles.add(title.trim().toLowerCase());
          }
        }
      }
      if (d.status === 'completed') existing.completed++;
      existing.total++;
      if (logDate >= today && d.studentId) {
        existing.todayReaders.add(d.studentId);
      }
      logsByClass.set(cid, existing);
    }

    return classesSnap.docs.map((doc) => {
      const data = doc.data();
      const studentCount = (data.studentIds ?? []).length;
      const logs = logsByClass.get(doc.id) ?? { minutes: 0, bookTitles: new Set(), completed: 0, total: 0, todayReaders: new Set() };

      return {
        classId: doc.id,
        name: data.name ?? '',
        yearLevel: data.yearLevel,
        studentCount,
        totalMinutes: logs.minutes,
        totalLogs: logs.total,
        booksRead: logs.bookTitles.size,
        completionRate: logs.total > 0 ? Math.round((logs.completed / logs.total) * 100) : 0,
        avgMinPerStudent: studentCount > 0 ? Math.round(logs.minutes / studentCount) : 0,
        readersToday: logs.todayReaders.size,
      };
    }).sort((a, b) => b.totalMinutes - a.totalMinutes);
  } catch {
    return [];
  }
}

export async function getAtRiskStudents(
  schoolId: string,
  daysThreshold: number,
  tz: string,
): Promise<AtRiskStudent[]> {
  try {
    const studentsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('students')
      .where('isActive', '==', true)
      .get();

    const classesSnap = await adminDb
      .collection('schools').doc(schoolId).collection('classes')
      .get();
    const classNames = new Map<string, string>();
    for (const doc of classesSnap.docs) {
      classNames.set(doc.id, doc.data().name ?? '');
    }

    // Calendar days in the school's timezone — "read yesterday evening" is 1
    // day ago even if fewer than 24 hours have elapsed. (The old elapsed-ms
    // floor undercounted by up to a day.) Future-dated data clamps to 0.
    const todayStr = localDateString(new Date(), tz);
    const results: AtRiskStudent[] = [];

    for (const doc of studentsSnap.docs) {
      const d = doc.data();
      const lastDate = d.stats?.lastReadingDate?.toDate?.() ?? null;
      const daysSince = lastDate
        ? Math.max(0, calendarDaysBetween(localDateString(lastDate, tz), todayStr))
        : 999;

      if (daysSince >= daysThreshold) {
        results.push({
          id: doc.id,
          name: `${d.firstName ?? ''} ${d.lastName ?? ''}`.trim(),
          classId: d.classId ?? '',
          className: classNames.get(d.classId ?? '') ?? '',
          currentReadingLevel: d.currentReadingLevel,
          lastReadingDate: lastDate?.toISOString() ?? null,
          daysSinceRead: daysSince,
          currentStreak: d.stats?.currentStreak ?? 0,
        });
      }
    }

    return results.sort((a, b) => b.daysSinceRead - a.daysSinceRead);
  } catch {
    return [];
  }
}

export async function getTopReaders(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  limit: number = 10,
  prefetchedLogs?: LogDoc[],
): Promise<TopReader[]> {
  try {
    const [studentsSnap, classesSnap, logDocs] = await Promise.all([
      adminDb.collection('schools').doc(schoolId).collection('students')
        .where('isActive', '==', true)
        .get(),
      adminDb.collection('schools').doc(schoolId).collection('classes').get(),
      prefetchedLogs ? Promise.resolve(prefetchedLogs) : fetchReadingLogsInRange(schoolId, startDate, endDate),
    ]);

    const classNames = new Map<string, string>();
    for (const doc of classesSnap.docs) {
      classNames.set(doc.id, doc.data().name ?? '');
    }

    const booksByStudent = new Map<string, Set<string>>();
    const minutesByStudent = new Map<string, number>();

    for (const doc of logDocs) {
      const d = doc.data();
      if (skipAsWeekend(weekdaysOnly, logDayKey(d, tz))) continue;
      const sid = d.studentId ?? '';
      if (!sid) continue;
      if (!booksByStudent.has(sid)) booksByStudent.set(sid, new Set());
      minutesByStudent.set(sid, (minutesByStudent.get(sid) ?? 0) + (d.minutesRead ?? 0));
      if (Array.isArray(d.bookTitles)) {
        for (const title of d.bookTitles) {
          if (typeof title === 'string' && title.trim()) {
            booksByStudent.get(sid)!.add(title.trim().toLowerCase());
          }
        }
      }
    }

    const readers: TopReader[] = studentsSnap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        name: `${d.firstName ?? ''} ${d.lastName ?? ''}`.trim(),
        className: classNames.get(d.classId ?? '') ?? '',
        totalMinutes: minutesByStudent.get(doc.id) ?? 0,
        uniqueBooks: booksByStudent.get(doc.id)?.size ?? 0,
        streak: d.stats?.currentStreak ?? 0,
      };
    });

    return readers
      .filter((r) => r.totalMinutes > 0)
      .sort((a, b) => b.totalMinutes - a.totalMinutes)
      .slice(0, limit);
  } catch {
    return [];
  }
}

export async function getPopularBooks(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean,
  tz: string,
  limit: number = 15,
  prefetchedLogs?: LogDoc[],
): Promise<PopularBook[]> {
  try {
    const logDocs = prefetchedLogs ?? (await fetchReadingLogsInRange(schoolId, startDate, endDate));

    const counts = new Map<string, number>();

    for (const doc of logDocs) {
      const d = doc.data();
      if (skipAsWeekend(weekdaysOnly, logDayKey(d, tz))) continue;
      const titles = d.bookTitles;
      if (Array.isArray(titles)) {
        for (const title of titles) {
          if (typeof title === 'string' && title.trim()) {
            const normalized = title.trim();
            counts.set(normalized, (counts.get(normalized) ?? 0) + 1);
          }
        }
      }
    }

    return Array.from(counts.entries())
      .map(([title, count]) => ({ title, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, limit);
  } catch {
    return [];
  }
}
