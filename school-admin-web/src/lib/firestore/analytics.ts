import { adminDb } from '@/lib/firebase/admin';

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

function daysAgo(days: number): Date {
  const d = new Date();
  d.setDate(d.getDate() - days);
  d.setHours(0, 0, 0, 0);
  return d;
}

function isWeekend(date: Date): boolean {
  const day = date.getDay();
  return day === 0 || day === 6;
}

export function resolvePeriod(
  period: string,
  termKey: string | null,
  termDates: Record<string, Date>,
  now: Date = new Date(),
): { startDate: Date; endDate: Date; weekdaysOnly: boolean } {
  if (period === '5days') {
    const weekdays: Date[] = [];
    const d = new Date(now);
    while (weekdays.length < 5) {
      d.setDate(d.getDate() - 1);
      if (!isWeekend(d)) weekdays.push(new Date(d));
    }
    const start = new Date(weekdays[weekdays.length - 1]);
    start.setHours(0, 0, 0, 0);
    return { startDate: start, endDate: now, weekdaysOnly: true };
  }

  if (period === 'month') {
    const start = new Date(now.getFullYear(), now.getMonth(), 1);
    return { startDate: start, endDate: now, weekdaysOnly: true };
  }

  if (period === 'term' && termKey) {
    const start = termDates[`${termKey}Start`];
    const end = termDates[`${termKey}End`] ?? now;
    return { startDate: start, endDate: end > now ? now : end, weekdaysOnly: false };
  }

  // year — derived from earliest term start to latest term end
  const termStarts = Object.entries(termDates)
    .filter(([k]) => k.endsWith('Start'))
    .map(([, v]) => v)
    .filter(Boolean)
    .sort((a, b) => a.getTime() - b.getTime());
  const termEnds = Object.entries(termDates)
    .filter(([k]) => k.endsWith('End'))
    .map(([, v]) => v)
    .filter(Boolean)
    .sort((a, b) => b.getTime() - a.getTime());
  const yearStart = termStarts[0] ?? new Date(now.getFullYear(), 0, 1);
  const yearEnd = termEnds[0] ?? now;
  return { startDate: yearStart, endDate: yearEnd > now ? now : yearEnd, weekdaysOnly: false };
}

// --- Query Functions ---

export async function getReadingMetrics(
  schoolId: string,
  startDate: Date,
  endDate: Date,
  weekdaysOnly: boolean = false,
): Promise<ReadingMetrics> {
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startDate)
      .where('date', '<=', endDate)
      .get();

    let totalMinutes = 0;
    let totalBooks = 0;
    let completedCount = 0;
    let totalLogs = 0;
    const readers = new Set<string>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date(0);
      if (weekdaysOnly && isWeekend(logDate)) continue;
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
  weekdaysOnly: boolean = false,
): Promise<EngagementPoint[]> {
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startDate)
      .where('date', '<=', endDate)
      .get();

    const byDate = new Map<string, { minutes: number; logs: number }>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date();
      if (weekdaysOnly && isWeekend(logDate)) continue;
      const key = logDate.toISOString().split('T')[0];
      const existing = byDate.get(key) ?? { minutes: 0, logs: 0 };
      existing.minutes += d.minutesRead ?? 0;
      existing.logs += 1;
      byDate.set(key, existing);
    }

    // Fill in days (skipping weekends when weekdaysOnly)
    const result: EngagementPoint[] = [];
    const current = new Date(startDate);
    const end = new Date(endDate);
    end.setHours(23, 59, 59, 999);

    while (current <= end) {
      if (!weekdaysOnly || !isWeekend(current)) {
        const key = current.toISOString().split('T')[0];
        const data = byDate.get(key) ?? { minutes: 0, logs: 0 };
        result.push({ date: key, ...data });
      }
      current.setDate(current.getDate() + 1);
    }

    return result;
  } catch {
    return [];
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
  weekdaysOnly: boolean = false,
): Promise<ClassComparisonRow[]> {
  try {
    const classesSnap = await adminDb
      .collection('schools').doc(schoolId).collection('classes')
      .where('isActive', '==', true)
      .get();

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startDate)
      .where('date', '<=', endDate)
      .get();

    const logsByClass = new Map<string, { minutes: number; bookTitles: Set<string>; completed: number; total: number; todayReaders: Set<string> }>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date(0);
      if (weekdaysOnly && isWeekend(logDate)) continue;
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

export async function getAtRiskStudents(schoolId: string, daysThreshold: number = 7): Promise<AtRiskStudent[]> {
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

    const now = new Date();
    const results: AtRiskStudent[] = [];

    for (const doc of studentsSnap.docs) {
      const d = doc.data();
      const lastDate = d.stats?.lastReadingDate?.toDate?.() ?? null;
      const daysSince = lastDate
        ? Math.floor((now.getTime() - lastDate.getTime()) / (1000 * 60 * 60 * 24))
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
  weekdaysOnly: boolean = false,
  limit: number = 10,
): Promise<TopReader[]> {
  try {
    const [studentsSnap, classesSnap, logsSnap] = await Promise.all([
      adminDb.collection('schools').doc(schoolId).collection('students')
        .where('isActive', '==', true)
        .get(),
      adminDb.collection('schools').doc(schoolId).collection('classes').get(),
      adminDb.collection('schools').doc(schoolId).collection('readingLogs')
        .where('date', '>=', startDate)
        .where('date', '<=', endDate)
        .get(),
    ]);

    const classNames = new Map<string, string>();
    for (const doc of classesSnap.docs) {
      classNames.set(doc.id, doc.data().name ?? '');
    }

    const booksByStudent = new Map<string, Set<string>>();
    const minutesByStudent = new Map<string, number>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date(0);
      if (weekdaysOnly && isWeekend(logDate)) continue;
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
  weekdaysOnly: boolean = false,
  limit: number = 15,
): Promise<PopularBook[]> {
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startDate)
      .where('date', '<=', endDate)
      .get();

    const counts = new Map<string, number>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const logDate: Date = d.date?.toDate?.() ?? new Date(0);
      if (weekdaysOnly && isWeekend(logDate)) continue;
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
