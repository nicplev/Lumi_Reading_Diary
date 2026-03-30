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
  totalBooks: number;
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

// --- Query Functions ---

export async function getReadingMetrics(schoolId: string, days: number = 30): Promise<ReadingMetrics> {
  const since = daysAgo(days);

  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', since)
      .get();

    let totalMinutes = 0;
    let totalBooks = 0;
    let completedCount = 0;
    const readers = new Set<string>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      totalMinutes += d.minutesRead ?? 0;
      if (Array.isArray(d.bookTitles)) totalBooks += d.bookTitles.length;
      if (d.status === 'completed') completedCount++;
      if (d.studentId) readers.add(d.studentId);
    }

    const totalLogs = logsSnap.size;
    const completionRate = totalLogs > 0 ? Math.round((completedCount / totalLogs) * 100) : 0;

    // Get total student count for avg calculation
    const schoolDoc = await adminDb.collection('schools').doc(schoolId).get();
    const studentCount = schoolDoc.data()?.studentCount ?? 1;
    const avgMinPerStudent = studentCount > 0 ? Math.round(totalMinutes / studentCount) : 0;

    return { totalMinutes, totalBooks, totalLogs, completionRate, avgMinPerStudent, uniqueReaders: readers.size };
  } catch {
    return { totalMinutes: 0, totalBooks: 0, totalLogs: 0, completionRate: 0, avgMinPerStudent: 0, uniqueReaders: 0 };
  }
}

export async function getEngagementTrend(schoolId: string, days: number = 30): Promise<EngagementPoint[]> {
  const since = daysAgo(days);

  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', since)
      .get();

    const byDate = new Map<string, { minutes: number; logs: number }>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const date = d.date?.toDate?.() ?? new Date();
      const key = date.toISOString().split('T')[0];
      const existing = byDate.get(key) ?? { minutes: 0, logs: 0 };
      existing.minutes += d.minutesRead ?? 0;
      existing.logs += 1;
      byDate.set(key, existing);
    }

    // Fill in missing days
    const result: EngagementPoint[] = [];
    const current = new Date(since);
    const today = new Date();
    today.setHours(23, 59, 59, 999);

    while (current <= today) {
      const key = current.toISOString().split('T')[0];
      const data = byDate.get(key) ?? { minutes: 0, logs: 0 };
      result.push({ date: key, ...data });
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

export async function getClassComparison(schoolId: string): Promise<ClassComparisonRow[]> {
  try {
    const classesSnap = await adminDb
      .collection('schools').doc(schoolId).collection('classes')
      .where('isActive', '==', true)
      .get();

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const thirtyDaysAgo = daysAgo(30);

    // Get all logs for last 30 days
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', thirtyDaysAgo)
      .get();

    // Group logs by classId
    const logsByClass = new Map<string, { minutes: number; books: number; completed: number; total: number; todayReaders: Set<string> }>();

    for (const doc of logsSnap.docs) {
      const d = doc.data();
      const cid = d.classId ?? '';
      const existing = logsByClass.get(cid) ?? { minutes: 0, books: 0, completed: 0, total: 0, todayReaders: new Set() };
      existing.minutes += d.minutesRead ?? 0;
      if (Array.isArray(d.bookTitles)) existing.books += d.bookTitles.length;
      if (d.status === 'completed') existing.completed++;
      existing.total++;
      const logDate = d.date?.toDate?.() ?? new Date(0);
      if (logDate >= today && d.studentId) {
        existing.todayReaders.add(d.studentId);
      }
      logsByClass.set(cid, existing);
    }

    return classesSnap.docs.map((doc) => {
      const data = doc.data();
      const studentCount = (data.studentIds ?? []).length;
      const logs = logsByClass.get(doc.id) ?? { minutes: 0, books: 0, completed: 0, total: 0, todayReaders: new Set() };

      return {
        classId: doc.id,
        name: data.name ?? '',
        yearLevel: data.yearLevel,
        studentCount,
        totalMinutes: logs.minutes,
        booksRead: logs.books,
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

    // Build class name map
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

export async function getTopReaders(schoolId: string, limit: number = 10): Promise<TopReader[]> {
  try {
    const studentsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('students')
      .where('isActive', '==', true)
      .get();

    // Build class name map
    const classesSnap = await adminDb
      .collection('schools').doc(schoolId).collection('classes')
      .get();
    const classNames = new Map<string, string>();
    for (const doc of classesSnap.docs) {
      classNames.set(doc.id, doc.data().name ?? '');
    }

    const readers: TopReader[] = studentsSnap.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        name: `${d.firstName ?? ''} ${d.lastName ?? ''}`.trim(),
        className: classNames.get(d.classId ?? '') ?? '',
        totalMinutes: d.stats?.totalMinutesRead ?? 0,
        totalBooks: d.stats?.totalBooksRead ?? 0,
        streak: d.stats?.currentStreak ?? 0,
      };
    });

    return readers
      .sort((a, b) => b.totalMinutes - a.totalMinutes)
      .slice(0, limit);
  } catch {
    return [];
  }
}

export async function getPopularBooks(schoolId: string, days: number = 30, limit: number = 15): Promise<PopularBook[]> {
  const since = daysAgo(days);

  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', since)
      .get();

    const counts = new Map<string, number>();

    for (const doc of logsSnap.docs) {
      const titles = doc.data().bookTitles;
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
