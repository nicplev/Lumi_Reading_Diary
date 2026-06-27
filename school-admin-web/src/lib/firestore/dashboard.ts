import { adminDb } from '@/lib/firebase/admin';

export interface DashboardStats {
  totalStudents: number;
  totalTeachers: number;
  totalClasses: number;
  activeStudentsToday: number;
}

export interface WeeklyEngagement {
  day: string;
  count: number;
}

export interface RecentActivity {
  id: string;
  studentName: string;
  action: string;
  time: Date;
  bookTitle?: string;
}

export async function getDashboardStats(schoolId: string): Promise<DashboardStats> {
  const schoolDoc = await adminDb.collection('schools').doc(schoolId).get();
  const schoolData = schoolDoc.data();

  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('isActive', '==', true)
    .get();

  // Get student count — use denormalized counter, but self-heal if it's 0
  let totalStudents = schoolData?.studentCount ?? 0;
  if (totalStudents === 0) {
    const studentsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('students')
      .where('isActive', '==', true)
      .get();
    totalStudents = studentsSnap.size;
    // Self-heal: update the school doc if count was wrong
    if (totalStudents > 0) {
      await adminDb.collection('schools').doc(schoolId).update({ studentCount: totalStudents });
    }
  }

  // Count active students today
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let activeStudentsToday = 0;
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', today)
      .get();

    // If date-based query returns nothing, try createdAt as fallback
    if (logsSnap.empty) {
      const fallbackSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('createdAt', '>=', today)
        .get();
      const uniqueStudents = new Set(fallbackSnap.docs.map(d => d.data().studentId));
      activeStudentsToday = uniqueStudents.size;
    } else {
      const uniqueStudents = new Set(logsSnap.docs.map(d => d.data().studentId));
      activeStudentsToday = uniqueStudents.size;
    }
  } catch {
    // readingLogs collection may not exist yet
  }

  return {
    totalStudents,
    totalTeachers: schoolData?.teacherCount ?? 0,
    totalClasses: classesSnap.size,
    activeStudentsToday,
  };
}

export async function getWeeklyEngagement(schoolId: string): Promise<WeeklyEngagement[]> {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const today = new Date();
  const startOfWeek = new Date(today);
  // Fix Sunday edge case: getDay() returns 0 for Sunday
  const dayOfWeek = today.getDay();
  const mondayOffset = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  startOfWeek.setDate(today.getDate() + mondayOffset);
  startOfWeek.setHours(0, 0, 0, 0);

  try {
    // Try date field first
    let logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get();

    // Fallback to createdAt if date field yields no results
    if (logsSnap.empty) {
      logsSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('createdAt', '>=', startOfWeek)
        .get();
    }

    const countByDay = new Map<number, number>();
    logsSnap.docs.forEach(doc => {
      const data = doc.data();
      // Handle both Timestamp and string date fields
      let date: Date;
      if (data.date?.toDate) {
        date = data.date.toDate();
      } else if (data.createdAt?.toDate) {
        date = data.createdAt.toDate();
      } else if (typeof data.date === 'string') {
        date = new Date(data.date);
      } else {
        date = new Date();
      }
      const dayIndex = (date.getDay() + 6) % 7; // Mon=0
      countByDay.set(dayIndex, (countByDay.get(dayIndex) ?? 0) + 1);
    });

    return days.map((day, i) => ({ day, count: countByDay.get(i) ?? 0 }));
  } catch {
    return days.map(day => ({ day, count: 0 }));
  }
}

export async function getRecentActivity(schoolId: string, limit = 5): Promise<RecentActivity[]> {
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .orderBy('createdAt', 'desc')
      .limit(limit)
      .get();

    // Batch fetch all student IDs at once instead of N+1 queries
    const studentIds = [...new Set(logsSnap.docs.map(d => d.data().studentId).filter(Boolean))];
    const studentNames = new Map<string, string>();

    // Firestore 'in' queries support max 30 items
    for (let i = 0; i < studentIds.length; i += 30) {
      const chunk = studentIds.slice(i, i + 30);
      try {
        const studentsSnap = await adminDb
          .collection('schools').doc(schoolId).collection('students')
          .where('__name__', 'in', chunk)
          .get();
        for (const doc of studentsSnap.docs) {
          const s = doc.data();
          studentNames.set(doc.id, `${s.firstName} ${s.lastName}`);
        }
      } catch { /* ignore */ }
    }

    return logsSnap.docs.map(doc => {
      const data = doc.data();
      const bookTitles = Array.isArray(data.bookTitles) ? data.bookTitles : [];
      const bookTitle = bookTitles[0]; // First book title for display
      const action = bookTitle
        ? `Read "${bookTitle}" — ${data.minutesRead ?? 0} min`
        : `Logged ${data.minutesRead ?? 0} min reading`;

      return {
        id: doc.id,
        studentName: studentNames.get(data.studentId) ?? 'Unknown Student',
        action,
        time: data.createdAt?.toDate?.() ?? new Date(),
        bookTitle,
      };
    });
  } catch {
    return [];
  }
}

export interface TeacherDashboardData {
  classes: Array<{
    id: string;
    name: string;
    yearLevel?: string;
    studentCount: number;
    readTodayCount: number;
  }>;
  totalStudents: number;
  readToday: number;
  onStreak: number;
  booksToday: number;
}

export async function getTeacherDashboardData(schoolId: string, userId: string): Promise<TeacherDashboardData> {
  // Get classes where this teacher is assigned
  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('teacherIds', 'array-contains', userId)
    .where('isActive', '==', true)
    .get();

  const today = new Date();
  today.setHours(0, 0, 0, 0);

  // Collect all student IDs and class IDs upfront
  const allStudentIds: string[] = [];
  const classIds: string[] = [];
  for (const classDoc of classesSnap.docs) {
    classIds.push(classDoc.id);
    const studentIds: string[] = classDoc.data().studentIds ?? [];
    allStudentIds.push(...studentIds);
  }

  // Batch fetch: today's logs for all teacher's classes in one query
  let allTodayLogs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', today)
      .get();
    // Filter client-side to teacher's classes (avoids needing composite index on classId+date)
    allTodayLogs = logsSnap.docs.filter(d => classIds.includes(d.data().classId));
  } catch { /* ignore */ }

  // Group logs by classId
  const logsByClass = new Map<string, typeof allTodayLogs>();
  for (const doc of allTodayLogs) {
    const cid = doc.data().classId;
    const existing = logsByClass.get(cid) ?? [];
    existing.push(doc);
    logsByClass.set(cid, existing);
  }

  // Batch fetch: all students in one query instead of N individual reads
  let onStreak = 0;
  if (allStudentIds.length > 0) {
    // Firestore 'in' queries support max 30 items, so chunk
    const uniqueIds = [...new Set(allStudentIds)];
    for (let i = 0; i < uniqueIds.length; i += 30) {
      const chunk = uniqueIds.slice(i, i + 30);
      try {
        const studentsSnap = await adminDb
          .collection('schools').doc(schoolId).collection('students')
          .where('__name__', 'in', chunk)
          .get();
        for (const doc of studentsSnap.docs) {
          if (doc.data().stats?.currentStreak > 0) onStreak++;
        }
      } catch { /* ignore */ }
    }
  }

  let totalStudents = 0;
  let readToday = 0;
  let booksToday = 0;
  const classes = [];

  for (const classDoc of classesSnap.docs) {
    const classData = classDoc.data();
    const studentIds: string[] = classData.studentIds ?? [];
    totalStudents += studentIds.length;

    const classLogs = logsByClass.get(classDoc.id) ?? [];
    const uniqueStudents = new Set(classLogs.map(d => d.data().studentId));
    const classReadToday = uniqueStudents.size;
    readToday += classReadToday;

    for (const d of classLogs) {
      const bookTitles = d.data().bookTitles;
      if (Array.isArray(bookTitles)) booksToday += bookTitles.length;
    }

    classes.push({
      id: classDoc.id,
      name: classData.name ?? '',
      yearLevel: classData.yearLevel,
      studentCount: studentIds.length,
      readTodayCount: classReadToday,
    });
  }

  return { classes, totalStudents, readToday, onStreak, booksToday };
}

export interface TeacherTopReader {
  studentId: string;
  name: string;
  minutes: number;
  characterId?: string;
}

export interface TeacherNudge {
  studentId: string;
  name: string;
  daysSinceRead: number | null; // null = never read
  characterId?: string;
}

export interface TeacherParentComment {
  logId: string;
  studentId: string;
  studentName: string;
  preview: string;
  at: Date;
  characterId?: string;
}

export interface TeacherSentiment {
  feeling: string;
  count: number;
}

export interface TeacherRecentReading {
  logId: string;
  studentId: string;
  studentName: string;
  books: string[];
  minutes: number;
  at: Date;
  characterId?: string;
}

export interface TeacherGroupComparison {
  groupId: string;
  name: string;
  color: string | null;
  totalStudents: number;
  activeReaders: number;
  totalMinutes: number;
  avgMinutes: number;
}

export interface TeacherRecentAchievement {
  studentId: string;
  studentName: string;
  name: string;
  icon: string;
  rarity: string;
  earnedAt: Date | null;
  characterId?: string;
}

export interface TeacherDashboardWidgets {
  topReaders: TeacherTopReader[];
  nudges: TeacherNudge[];
  parentComments: TeacherParentComment[];
  sentiment: TeacherSentiment[];
  recentReading: TeacherRecentReading[];
  groupComparison: TeacherGroupComparison[];
  recentAchievements: TeacherRecentAchievement[];
}

/**
 * The "key widgets" for the teacher dashboard, scoped to the teacher's classes:
 * top readers this week, students needing attention (no read in 3+ days), and
 * unread parent comments. Reuses the same single this-week-logs scan the rest of
 * the dashboard uses (no new index).
 */
export async function getTeacherDashboardWidgets(
  schoolId: string,
  userId: string
): Promise<TeacherDashboardWidgets> {
  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('teacherIds', 'array-contains', userId)
    .where('isActive', '==', true)
    .get();

  const classIds = classesSnap.docs.map((d) => d.id);
  const studentIds = [...new Set(classesSnap.docs.flatMap((d) => (d.data().studentIds ?? []) as string[]))];
  if (classIds.length === 0)
    return {
      topReaders: [],
      nudges: [],
      parentComments: [],
      sentiment: [],
      recentReading: [],
      groupComparison: [],
      recentAchievements: [],
    };

  // Student names + last reading date (for top readers labels + nudges) and any
  // earned achievements (for the achievement-spotlight widget) — all read from
  // the student docs we already fetch here, so no extra reads.
  const nameById = new Map<string, string>();
  const characterById = new Map<string, string | undefined>();
  const lastReadById = new Map<string, Date | null>();
  const recentAchievements: TeacherRecentAchievement[] = [];
  for (let i = 0; i < studentIds.length; i += 30) {
    const chunk = studentIds.slice(i, i + 30);
    try {
      const snap = await adminDb
        .collection('schools').doc(schoolId).collection('students')
        .where('__name__', 'in', chunk)
        .get();
      for (const doc of snap.docs) {
        const s = doc.data();
        const studentName = `${s.firstName ?? ''} ${s.lastName ?? ''}`.trim();
        nameById.set(doc.id, studentName);
        characterById.set(doc.id, s.characterId);
        lastReadById.set(doc.id, s.stats?.lastReadingDate?.toDate?.() ?? null);
        if (Array.isArray(s.achievements)) {
          for (const a of s.achievements) {
            recentAchievements.push({
              studentId: doc.id,
              studentName: studentName || 'Student',
              name: a.name ?? '',
              icon: a.icon ?? '🏅',
              rarity: a.rarity ?? 'common',
              earnedAt: a.earnedAt?.toDate?.() ?? null,
              characterId: s.characterId,
            });
          }
        }
      }
    } catch { /* ignore */ }
  }

  const startOfWeek = new Date();
  const dow = startOfWeek.getDay();
  startOfWeek.setDate(startOfWeek.getDate() + (dow === 0 ? -6 : 1 - dow));
  startOfWeek.setHours(0, 0, 0, 0);

  const minutesByStudent = new Map<string, number>();
  const parentComments: TeacherParentComment[] = [];
  const feelingCounts = new Map<string, number>();
  const recentReading: TeacherRecentReading[] = [];
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get();
    for (const doc of logsSnap.docs) {
      const d = doc.data();
      if (!classIds.includes(d.classId)) continue;
      const sid: string = d.studentId ?? '';
      if (!sid) continue;
      const minutes = d.minutesRead ?? 0;
      minutesByStudent.set(sid, (minutesByStudent.get(sid) ?? 0) + minutes);

      if (typeof d.childFeeling === 'string' && d.childFeeling) {
        feelingCounts.set(d.childFeeling, (feelingCounts.get(d.childFeeling) ?? 0) + 1);
      }

      const readAt: Date | null = d.date?.toDate?.() ?? d.createdAt?.toDate?.() ?? null;
      if (readAt) {
        recentReading.push({
          logId: doc.id,
          studentId: sid,
          studentName: nameById.get(sid) ?? 'Student',
          books: Array.isArray(d.bookTitles) ? d.bookTitles : [],
          minutes,
          at: readAt,
          characterId: characterById.get(sid),
        });
      }

      const lastAt: Date | null = d.lastCommentAt?.toDate?.() ?? null;
      if (lastAt && d.lastCommentByRole === 'parent') {
        const viewed: Date | null = d.commentsViewedAt?.[userId]?.toDate?.() ?? null;
        if (!viewed || viewed < lastAt) {
          parentComments.push({
            logId: doc.id,
            studentId: sid,
            studentName: nameById.get(sid) ?? 'Student',
            preview: d.lastCommentPreview ?? '',
            at: lastAt,
            characterId: characterById.get(sid),
          });
        }
      }
    }
  } catch { /* ignore */ }

  // Reading-group comparison — bucket this week's minutes by group membership.
  // `classId in` is a single-field filter (no composite index); isActive is
  // filtered client-side to avoid one.
  const groupComparison: TeacherGroupComparison[] = [];
  try {
    const groupDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    for (let i = 0; i < classIds.length; i += 30) {
      const chunk = classIds.slice(i, i + 30);
      const snap = await adminDb
        .collection('schools').doc(schoolId).collection('readingGroups')
        .where('classId', 'in', chunk)
        .get();
      groupDocs.push(...snap.docs);
    }
    for (const g of groupDocs) {
      const data = g.data();
      if (data.isActive === false) continue;
      const members: string[] = Array.isArray(data.studentIds) ? data.studentIds : [];
      let activeReaders = 0;
      let totalMinutes = 0;
      for (const sid of members) {
        const m = minutesByStudent.get(sid) ?? 0;
        if (m > 0) activeReaders++;
        totalMinutes += m;
      }
      groupComparison.push({
        groupId: g.id,
        name: data.name ?? 'Group',
        color: data.color ?? null,
        totalStudents: members.length,
        activeReaders,
        totalMinutes,
        avgMinutes: members.length > 0 ? Math.round(totalMinutes / members.length) : 0,
      });
    }
    groupComparison.sort((a, b) => b.totalMinutes - a.totalMinutes);
  } catch { /* ignore */ }

  const FEELING_ORDER = ['hard', 'tricky', 'okay', 'good', 'great'];
  const sentiment: TeacherSentiment[] = FEELING_ORDER.map((feeling) => ({
    feeling,
    count: feelingCounts.get(feeling) ?? 0,
  }));

  recentReading.sort((a, b) => b.at.getTime() - a.at.getTime());
  recentAchievements.sort((a, b) => (b.earnedAt?.getTime() ?? 0) - (a.earnedAt?.getTime() ?? 0));

  const topReaders = [...minutesByStudent.entries()]
    .filter(([sid, m]) => m > 0 && nameById.has(sid))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([sid, m]) => ({
      studentId: sid,
      name: nameById.get(sid) ?? 'Student',
      minutes: m,
      characterId: characterById.get(sid),
    }));

  const now = Date.now();
  const nudges = studentIds
    // Skip ids that don't resolve to a current student doc — orphaned ids in the
    // class's studentIds array otherwise render as ghost "Student / Not read yet"
    // rows. (Real students always resolve via the batch fetch above.)
    .filter((sid) => nameById.has(sid))
    .map((sid) => {
      const last = lastReadById.get(sid) ?? null;
      const daysSinceRead = last ? Math.floor((now - last.getTime()) / 86_400_000) : null;
      return {
        studentId: sid,
        name: nameById.get(sid) ?? 'Student',
        daysSinceRead,
        characterId: characterById.get(sid),
      };
    })
    .filter((n) => n.daysSinceRead === null || n.daysSinceRead >= 3)
    .sort((a, b) => (b.daysSinceRead ?? 99_999) - (a.daysSinceRead ?? 99_999))
    .slice(0, 20);

  parentComments.sort((a, b) => b.at.getTime() - a.at.getTime());

  return {
    topReaders,
    nudges,
    parentComments: parentComments.slice(0, 20),
    sentiment,
    recentReading: recentReading.slice(0, 20),
    groupComparison: groupComparison.slice(0, 12),
    recentAchievements: recentAchievements.slice(0, 15),
  };
}

export interface ReadingCalendarDay {
  /** yyyy-mm-dd in the server's local time, matching the rest of the dashboard. */
  date: string;
  count: number;
}

/**
 * Daily reading-log counts across the teacher's classes for the last `weeks`
 * weeks (oldest first, zero-filled) — powers the dashboard heatmap. One
 * single-field `date >=` scan filtered to the teacher's classes client-side:
 * the same index the other dashboard scans use, just a wider window. Fetched
 * lazily by the calendar widget so this heavier scan only runs when it's shown.
 */
export async function getTeacherReadingCalendar(
  schoolId: string,
  userId: string,
  weeks = 6
): Promise<ReadingCalendarDay[]> {
  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('teacherIds', 'array-contains', userId)
    .where('isActive', '==', true)
    .get();
  const classIds = new Set(classesSnap.docs.map((d) => d.id));
  if (classIds.size === 0) return [];

  const span = weeks * 7;
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  start.setDate(start.getDate() - (span - 1));

  const pad = (n: number) => String(n).padStart(2, '0');
  const dateKey = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  const counts = new Map<string, number>();
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', start)
      .get();
    for (const doc of logsSnap.docs) {
      const d = doc.data();
      if (!classIds.has(d.classId)) continue;
      const when: Date | null = d.date?.toDate?.() ?? d.createdAt?.toDate?.() ?? null;
      if (!when) continue;
      const key = dateKey(when);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  } catch { /* ignore */ }

  // Emit every day in the window (including zero-count days) so the heatmap grid
  // is complete and weekday-aligned in the component.
  const out: ReadingCalendarDay[] = [];
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const cursor = new Date(start);
  while (cursor <= today) {
    const key = dateKey(cursor);
    out.push({ date: key, count: counts.get(key) ?? 0 });
    cursor.setDate(cursor.getDate() + 1);
  }
  return out;
}
