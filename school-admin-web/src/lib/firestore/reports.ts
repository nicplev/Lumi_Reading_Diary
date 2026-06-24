import { adminDb } from '@/lib/firebase/admin';
import { getClass } from './classes';
import { getStudents } from './students';

export interface ClassReportStudentRow {
  id: string;
  name: string;
  minutes: number;
  sessions: number;
  readingDays: number;
  books: number;
  metPct: number;
  currentReadingLevel: string | null;
}

export interface ClassReportSupportRow {
  id: string;
  name: string;
  minutes: number;
  readingDays: number;
  issue: string;
}

export interface ClassReport {
  classId: string;
  className: string;
  yearLevel: string | null;
  from: string;
  to: string;
  totalStudents: number;
  activeReaders: number;
  engagementRate: number;
  totalMinutes: number;
  avgMinutesPerStudent: number;
  totalBooks: number;
  totalSessions: number;
  studentsMetTarget: number;
  targetMetRate: number;
  longestStreak: number;
  popularLevel: string | null;
  topReaders: ClassReportStudentRow[];
  needsSupport: ClassReportSupportRow[];
  levelDistribution: { level: string; count: number }[];
}

function dayKey(d: Date): string {
  return d.toISOString().slice(0, 10);
}

interface Acc {
  minutes: number;
  sessions: number;
  days: Set<string>;
  books: Set<string>;
  met: number;
}

/**
 * Per-class reading report over a date range. Mirrors the app's
 * class_report_screen / pdf_report_service definitions:
 * - active reader = any minutes in range
 * - met target = log.minutesRead >= (log.targetMinutes || class default)
 * - student "met target" = >= 70% of their logs met target
 * - needs support = no logs, OR < 3 reading days, OR < 50% met target
 */
export async function getClassReport(
  schoolId: string,
  classId: string,
  startDate: Date,
  endDate: Date
): Promise<ClassReport> {
  const [cls, students] = await Promise.all([
    getClass(schoolId, classId),
    getStudents(schoolId, { classId, isActive: true }),
  ]);

  const defaultTarget = cls?.defaultMinutesTarget ?? 20;

  const logsSnap = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('readingLogs')
    .where('classId', '==', classId)
    .where('date', '>=', startDate)
    .where('date', '<=', endDate)
    .get();

  const acc = new Map<string, Acc>();
  const classBooks = new Set<string>();

  for (const doc of logsSnap.docs) {
    const d = doc.data();
    const sid: string = d.studentId ?? '';
    if (!sid) continue;
    const a = acc.get(sid) ?? { minutes: 0, sessions: 0, days: new Set(), books: new Set(), met: 0 };
    const mins: number = d.minutesRead ?? 0;
    a.minutes += mins;
    a.sessions += 1;
    const dt: Date | null = d.date?.toDate?.() ?? null;
    if (dt) a.days.add(dayKey(dt));
    if (Array.isArray(d.bookTitles)) {
      for (const t of d.bookTitles) {
        if (typeof t === 'string' && t.trim()) {
          const key = t.trim().toLowerCase();
          a.books.add(key);
          classBooks.add(key);
        }
      }
    }
    const target = typeof d.targetMinutes === 'number' && d.targetMinutes > 0 ? d.targetMinutes : defaultTarget;
    if (mins >= target) a.met += 1;
    acc.set(sid, a);
  }

  const rows: ClassReportStudentRow[] = students.map((s) => {
    const a = acc.get(s.id);
    const sessions = a?.sessions ?? 0;
    return {
      id: s.id,
      name: `${s.firstName ?? ''} ${s.lastName ?? ''}`.trim(),
      minutes: a?.minutes ?? 0,
      sessions,
      readingDays: a?.days.size ?? 0,
      books: a?.books.size ?? 0,
      metPct: sessions > 0 ? Math.round(((a?.met ?? 0) / sessions) * 100) : 0,
      currentReadingLevel: s.currentReadingLevel ?? null,
    };
  });

  const totalStudents = students.length;
  const activeReaders = rows.filter((r) => r.minutes > 0).length;
  const totalMinutes = rows.reduce((sum, r) => sum + r.minutes, 0);
  const totalSessions = rows.reduce((sum, r) => sum + r.sessions, 0);
  const studentsMetTarget = rows.filter((r) => r.sessions > 0 && r.metPct >= 70).length;
  const longestStreak = students.reduce((m, s) => Math.max(m, s.stats?.longestStreak ?? 0), 0);

  const levelCounts = new Map<string, number>();
  for (const s of students) {
    const lvl = s.currentReadingLevel?.trim() || 'No Level';
    levelCounts.set(lvl, (levelCounts.get(lvl) ?? 0) + 1);
  }
  const levelDistribution = [...levelCounts.entries()]
    .map(([level, count]) => ({ level, count }))
    .sort((a, b) => b.count - a.count);
  const popularLevel = levelDistribution.find((l) => l.level !== 'No Level')?.level ?? null;

  const topReaders = rows
    .filter((r) => r.minutes > 0)
    .sort((a, b) => b.minutes - a.minutes)
    .slice(0, 10);

  const needsSupport: ClassReportSupportRow[] = rows
    .filter((r) => r.sessions === 0 || r.readingDays < 3 || r.metPct < 50)
    .map((r) => ({
      id: r.id,
      name: r.name,
      minutes: r.minutes,
      readingDays: r.readingDays,
      issue: r.sessions === 0 ? 'No reading logged' : r.readingDays < 3 ? 'Low engagement' : 'Not meeting targets',
    }))
    .slice(0, 10);

  return {
    classId,
    className: cls?.name ?? '',
    yearLevel: cls?.yearLevel ?? null,
    from: startDate.toISOString(),
    to: endDate.toISOString(),
    totalStudents,
    activeReaders,
    engagementRate: totalStudents > 0 ? Math.round((activeReaders / totalStudents) * 100) : 0,
    totalMinutes,
    avgMinutesPerStudent: totalStudents > 0 ? Math.round(totalMinutes / totalStudents) : 0,
    totalBooks: classBooks.size,
    totalSessions,
    studentsMetTarget,
    targetMetRate: totalStudents > 0 ? Math.round((studentsMetTarget / totalStudents) * 100) : 0,
    longestStreak,
    popularLevel,
    topReaders,
    needsSupport,
    levelDistribution,
  };
}
