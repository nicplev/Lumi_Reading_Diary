import { adminDb } from '@/lib/firebase/admin';
import {
  DEFAULT_TIMEZONE,
  getSchoolTimezone,
  localDateString,
  localWeekdayIndex,
  shiftDateStr,
  startOfLocalDay,
  startOfLocalWeek,
  zonedDayStart,
} from '@/lib/school-time';
import {
  getCurrentAcademicYear,
  isSchoolSubActive,
  isStudentAccessLive,
} from '@/lib/access';

export interface DashboardStats {
  totalStudents: number;
  totalTeachers: number;
  totalClasses: number;
  activeStudentsToday: number;
}

export interface WeeklyEngagement {
  day: string;
  count: number;
  minutes: number;
}

export interface WeeklyClassSeries {
  /** Classes with at least one reading log this week, sorted by name. */
  classes: { id: string; name: string }[];
  /** One row per weekday; per class two keys: `${id}:count` and `${id}:minutes`. */
  rows: Array<Record<string, number | string>>;
}

export interface RecentActivity {
  id: string;
  studentName: string;
  action: string;
  time: Date;
  bookTitle?: string;
}

/**
 * One `classes where isActive` snapshot, shared by getDashboardStats and
 * getOperationalSummary — the admin dashboard render fired both, each with
 * its own identical query. Fetch once in the page and pass down.
 */
export async function fetchActiveClasses(
  schoolId: string,
): Promise<FirebaseFirestore.QuerySnapshot> {
  return adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('isActive', '==', true)
    .get();
}

/**
 * One whole-school reading-log scan covering the current school-local week
 * (Monday-anchored, `date >=` only — same window `getTeacherDashboardWidgets`
 * used), shared by the three teacher-dashboard functions that previously
 * each ran their own overlapping whole-school scan per render:
 * today (getTeacherDashboardData) ⊂ week, and getWeeklyEngagement's
 * weekOffset-0 window is this week bounded above.
 */
export interface WeekLogsPrefetch {
  docs: FirebaseFirestore.QueryDocumentSnapshot[];
  tz: string;
}

export async function fetchCurrentWeekLogs(
  schoolId: string,
): Promise<WeekLogsPrefetch> {
  const tz = await getSchoolTimezone(schoolId);
  const startOfWeek = startOfLocalWeek(new Date(), tz);
  const snap = await adminDb
    .collection('schools').doc(schoolId).collection('readingLogs')
    .where('date', '>=', startOfWeek)
    .get();
  return { docs: snap.docs, tz };
}

export async function getDashboardStats(
  schoolId: string,
  prefetchedClasses?: FirebaseFirestore.QuerySnapshot,
): Promise<DashboardStats> {
  const schoolDoc = await adminDb.collection('schools').doc(schoolId).get();
  const schoolData = schoolDoc.data();

  const classesSnap = prefetchedClasses ?? await adminDb
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

  // Count active students today (school-local day, not server midnight)
  const tz = typeof schoolData?.timezone === 'string' && schoolData.timezone
    ? schoolData.timezone : DEFAULT_TIMEZONE;
  const today = startOfLocalDay(new Date(), tz);

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

/**
 * Operational signals for the admin dashboard — the "what needs my attention"
 * counts that drive the Attention Required card, the overview-card subtitles and
 * the Needs-attention tile. Every field is derived from collections the portal
 * already owns (no new functions/rules/indexes): students, classes, the
 * top-level studentLinkCodes (the parent-invite mechanism), scheduled
 * notificationCampaigns, and users (for an accurate, drift-free staff count plus
 * the temp-password-pending invite proxy). Each read is isolated so one failing
 * query degrades to 0 rather than blanking the whole dashboard.
 */
export interface OperationalSummary {
  /** Active staff docs (teachers + admins) — accurate count, not the drift-prone counter. */
  activeStaff: number;
  /** Staff issued a temp password who haven't logged in since (invite still pending). */
  pendingStaffInvites: number;
  /** Active students with no class (classId empty/unset). */
  unassignedStudents: number;
  /** Active students with no linked guardian. */
  studentsWithoutGuardian: number;
  /** Active classes with no assigned teacher. */
  classesWithoutTeacher: number;
  /** Live, non-expired parent link codes awaiting redemption. */
  pendingParentInvites: number;
  /** Announcements queued to send at a future time. */
  scheduledAnnouncements: number;
  // ── Setup-checklist signals (each is "has the school done this step yet") ──
  /** Active classes. */
  totalClasses: number;
  /** Active teacher-role users (excludes admins, so it isn't trivially ≥1). */
  activeTeachers: number;
  /** Active students with at least one linked guardian. */
  guardiansLinked: number;
  /** Real (non-placeholder) books in the library. */
  libraryBooks: number;
  /** Placeholder / untitled books — added but never resolved to real metadata. */
  incompleteBooks: number;
  // ── Access entitlement (the fail-closed Day-1 blocker) ──────────────────────
  /** Active students whose `access` map isn't live — their parents can't log. */
  studentsWithoutAccess: number;
  /** The academic year the portal would activate access for. */
  currentAcademicYear: number;
  /** Whether the school subscription for the current year is active (→ the
   *  admin can self-activate; if false they must contact Lumi). */
  subActiveForCurrentYear: boolean;
}

export async function getOperationalSummary(
  schoolId: string,
  prefetchedClasses?: FirebaseFirestore.QuerySnapshot,
): Promise<OperationalSummary> {
  const schoolRef = adminDb.collection('schools').doc(schoolId);

  const [studentsSnap, classesSnap, linkSnap, campaignSnap, usersSnap, booksSnap] = await Promise.all([
    schoolRef.collection('students').where('isActive', '==', true).get().catch(() => null),
    prefetchedClasses ??
      schoolRef.collection('classes').where('isActive', '==', true).get().catch(() => null),
    adminDb
      .collection('studentLinkCodes')
      .where('schoolId', '==', schoolId)
      .where('status', '==', 'active')
      .get()
      .catch(() => null),
    schoolRef.collection('notificationCampaigns').where('status', '==', 'scheduled').get().catch(() => null),
    schoolRef.collection('users').get().catch(() => null),
    schoolRef.collection('books').get().catch(() => null),
  ]);

  const now = new Date();

  const unassignedStudents = (studentsSnap?.docs ?? []).filter((d) => {
    const c = d.data().classId;
    return !c || c === '';
  }).length;

  const studentsWithoutGuardian = (studentsSnap?.docs ?? []).filter((d) => {
    const p = d.data().parentIds;
    return !Array.isArray(p) || p.length === 0;
  }).length;

  const totalActiveStudents = studentsSnap?.size ?? 0;
  const guardiansLinked = totalActiveStudents - studentsWithoutGuardian;

  // Access entitlement: how many active students can't have reading logged
  // because their `access` map isn't live (the fail-closed Day-1 blocker),
  // and whether the admin can self-activate (subscription active) or must
  // contact Lumi. Two tiny extra reads (year config + one subscription doc).
  const studentsWithoutAccess = (studentsSnap?.docs ?? []).filter(
    (d) =>
      d.data().access?.status !== 'revoked' &&
      !isStudentAccessLive(d.data().access, now)
  ).length;
  let currentAcademicYear = new Date().getUTCFullYear();
  let subActiveForCurrentYear = false;
  try {
    currentAcademicYear = await getCurrentAcademicYear();
    subActiveForCurrentYear = await isSchoolSubActive(schoolId, currentAcademicYear);
  } catch {
    // Non-fatal — the card just shows "contact Lumi" if we can't confirm.
  }

  // Placeholder books = the same ones getBooks() hides (no title or an explicit
  // placeholder flag) — added by ISBN but never resolved to real metadata.
  const incompleteBooks = (booksSnap?.docs ?? []).filter((d) => {
    const data = d.data();
    return !data.title || data.metadata?.placeholder === true;
  }).length;
  const libraryBooks = (booksSnap?.size ?? 0) - incompleteBooks;

  const activeTeachers = (usersSnap?.docs ?? []).filter((d) => {
    const data = d.data();
    return data.role === 'teacher' && data.isActive !== false;
  }).length;

  const classesWithoutTeacher = (classesSnap?.docs ?? []).filter((d) => {
    const t = d.data().teacherIds;
    return !Array.isArray(t) || t.length === 0;
  }).length;

  // Active codes only; drop any that are technically active but past expiry
  // (the sweep cron may not have run yet).
  const pendingParentInvites = (linkSnap?.docs ?? []).filter((d) => {
    const e = d.data().expiresAt?.toDate?.();
    return !e || e > now;
  }).length;

  const scheduledAnnouncements = campaignSnap?.size ?? 0;

  const activeStaff = (usersSnap?.docs ?? []).filter((d) => d.data().isActive !== false).length;

  // Pending staff invite = temp password issued and not logged in since (mirrors
  // isTempPasswordPending in users.ts; the indicator self-clears on first login).
  const pendingStaffInvites = (usersSnap?.docs ?? []).filter((d) => {
    const data = d.data();
    const tpc = data.tempPasswordCreatedAt?.toDate?.();
    if (!tpc) return false;
    const last = data.lastLoginAt?.toDate?.();
    return !last || last < tpc;
  }).length;

  return {
    activeStaff,
    pendingStaffInvites,
    unassignedStudents,
    studentsWithoutGuardian,
    classesWithoutTeacher,
    pendingParentInvites,
    scheduledAnnouncements,
    totalClasses: classesSnap?.size ?? 0,
    activeTeachers,
    guardiansLinked,
    libraryBooks,
    incompleteBooks,
    studentsWithoutAccess,
    currentAcademicYear,
    subActiveForCurrentYear,
  };
}

export interface WeeklyReadingSummary {
  /** Total minutes read so far this week (Mon-anchored). */
  minutes: number;
  /** Reading-log count this week. */
  logs: number;
  /** Distinct students who logged at least once this week. */
  uniqueReaders: number;
}

/**
 * A single-number snapshot of this week's reading for the dashboard's compact
 * "Reading this week" preview — the bridge into the full Analytics page. One
 * this-week log scan (the same `date >=` index the rest of the dashboard uses),
 * replacing the heavier per-class multi-line chart the dashboard used to draw.
 */
export async function getWeeklyReadingSummary(schoolId: string): Promise<WeeklyReadingSummary> {
  const tz = await getSchoolTimezone(schoolId);
  const startOfWeek = startOfLocalWeek(new Date(), tz);

  try {
    let logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get();
    if (logsSnap.empty) {
      logsSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('createdAt', '>=', startOfWeek)
        .get();
    }

    let minutes = 0;
    const readers = new Set<string>();
    logsSnap.docs.forEach((doc) => {
      const data = doc.data();
      minutes += typeof data.minutesRead === 'number' ? data.minutesRead : 0;
      if (data.studentId) readers.add(data.studentId);
    });

    return { minutes, logs: logsSnap.size, uniqueReaders: readers.size };
  } catch {
    return { minutes: 0, logs: 0, uniqueReaders: 0 };
  }
}

/**
 * Per-weekday log counts + minutes for one Monday-anchored school-local week.
 * `weekOffset` selects the week: 0 = this week, -1 = last week, etc — the
 * dashboard's timeframe selector drives it (a teacher checking Monday morning
 * flips to last week instead of staring at an empty chart).
 */
export async function getWeeklyEngagement(
  schoolId: string,
  weekOffset = 0,
  prefetched?: WeekLogsPrefetch,
): Promise<WeeklyEngagement[]> {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const tz = prefetched?.tz ?? await getSchoolTimezone(schoolId);
  const now = new Date();
  const thisMondayStr = shiftDateStr(localDateString(now, tz), -localWeekdayIndex(now, tz));
  const weekStartStr = shiftDateStr(thisMondayStr, 7 * weekOffset);
  const startOfWeek = zonedDayStart(weekStartStr, tz);
  const endOfWeek = zonedDayStart(shiftDateStr(weekStartStr, 7), tz);

  try {
    // Current week + prefetch available: filter the shared scan in memory
    // (it's `date >= startOfWeek`, superset of this bounded window).
    // Otherwise query the date field directly.
    let logDocs: FirebaseFirestore.QueryDocumentSnapshot[];
    if (prefetched && weekOffset === 0) {
      logDocs = prefetched.docs.filter(doc => {
        const ts = doc.data().date;
        const ms = ts?.toMillis?.();
        return typeof ms === 'number' &&
          ms >= startOfWeek.getTime() && ms < endOfWeek.getTime();
      });
    } else {
      const logsSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('date', '>=', startOfWeek)
        .where('date', '<', endOfWeek)
        .get();
      logDocs = logsSnap.docs;
    }

    // Fallback to createdAt if date field yields no results
    if (logDocs.length === 0) {
      const fallbackSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('createdAt', '>=', startOfWeek)
        .where('createdAt', '<', endOfWeek)
        .get();
      logDocs = fallbackSnap.docs;
    }

    const countByDay = new Map<number, number>();
    const minutesByDay = new Map<number, number>();
    logDocs.forEach(doc => {
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
      const dayIndex = localWeekdayIndex(date, tz); // Mon=0, school-local
      countByDay.set(dayIndex, (countByDay.get(dayIndex) ?? 0) + 1);
      const mins = typeof data.minutesRead === 'number' ? data.minutesRead : 0;
      minutesByDay.set(dayIndex, (minutesByDay.get(dayIndex) ?? 0) + mins);
    });

    return days.map((day, i) => ({ day, count: countByDay.get(i) ?? 0, minutes: minutesByDay.get(i) ?? 0 }));
  } catch {
    return days.map(day => ({ day, count: 0, minutes: 0 }));
  }
}

/**
 * Per-class weekly engagement — one series per class that has logged reading
 * this week (count + minutes per day). Powers the admin dashboard's multi-line
 * "how is each class tracking" chart. Classes with no activity this week are
 * intentionally omitted to keep the chart legible.
 */
export async function getWeeklyClassEngagement(schoolId: string): Promise<WeeklyClassSeries> {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const tz = await getSchoolTimezone(schoolId);
  const startOfWeek = startOfLocalWeek(new Date(), tz);

  const emptyRows = () => days.map((day) => ({ day }) as Record<string, number | string>);

  try {
    let logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get();
    if (logsSnap.empty) {
      logsSnap = await adminDb
        .collection('schools').doc(schoolId).collection('readingLogs')
        .where('createdAt', '>=', startOfWeek)
        .get();
    }
    if (logsSnap.empty) return { classes: [], rows: emptyRows() };

    // Resolve class names once.
    const classesSnap = await adminDb.collection('schools').doc(schoolId).collection('classes').get();
    const classNames = new Map<string, string>();
    classesSnap.docs.forEach((d) => {
      const data = d.data();
      classNames.set(d.id, (data.name as string) || (data.yearLevel as string) || 'Class');
    });

    // Aggregate per class → 7-day count + minutes arrays (Mon=0).
    const agg = new Map<string, { count: number[]; minutes: number[] }>();
    logsSnap.docs.forEach((doc) => {
      const data = doc.data();
      const classId = data.classId as string | undefined;
      if (!classId) return;
      let date: Date;
      if (data.date?.toDate) date = data.date.toDate();
      else if (data.createdAt?.toDate) date = data.createdAt.toDate();
      else if (typeof data.date === 'string') date = new Date(data.date);
      else date = new Date();
      const dayIndex = localWeekdayIndex(date, tz); // Mon=0, school-local
      if (!agg.has(classId)) agg.set(classId, { count: Array(7).fill(0), minutes: Array(7).fill(0) });
      const a = agg.get(classId)!;
      a.count[dayIndex] += 1;
      a.minutes[dayIndex] += typeof data.minutesRead === 'number' ? data.minutesRead : 0;
    });

    const classes = Array.from(agg.keys())
      .map((id) => ({ id, name: classNames.get(id) ?? 'Unknown class' }))
      .sort((x, y) => x.name.localeCompare(y.name));

    const rows = days.map((day, i) => {
      const row: Record<string, number | string> = { day };
      for (const c of classes) {
        const a = agg.get(c.id)!;
        row[`${c.id}:count`] = a.count[i];
        row[`${c.id}:minutes`] = a.minutes[i];
      }
      return row;
    });

    return { classes, rows };
  } catch {
    return { classes: [], rows: emptyRows() };
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

export async function getTeacherDashboardData(
  schoolId: string,
  userId: string,
  prefetched?: WeekLogsPrefetch,
): Promise<TeacherDashboardData> {
  // Get classes where this teacher is assigned
  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('teacherIds', 'array-contains', userId)
    .where('isActive', '==', true)
    .get();

  const tz = prefetched?.tz ?? await getSchoolTimezone(schoolId);
  const today = startOfLocalDay(new Date(), tz);

  // Collect all student IDs and class IDs upfront
  const allStudentIds: string[] = [];
  const classIds: string[] = [];
  for (const classDoc of classesSnap.docs) {
    classIds.push(classDoc.id);
    const studentIds: string[] = classDoc.data().studentIds ?? [];
    allStudentIds.push(...studentIds);
  }

  // Today's logs for all teacher's classes: today ⊂ current week, so the
  // shared week prefetch covers it in memory; otherwise one query.
  // Filter client-side to teacher's classes (avoids needing composite index on classId+date)
  let allTodayLogs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  try {
    const weekDocs = prefetched?.docs ?? (await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', today)
      .get()).docs;
    allTodayLogs = weekDocs.filter(d => {
      const ms = d.data().date?.toMillis?.();
      if (typeof ms !== 'number' || ms < today.getTime()) return false;
      return classIds.includes(d.data().classId);
    });
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
  userId: string,
  prefetched?: WeekLogsPrefetch,
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

  const startOfWeek = startOfLocalWeek(
    new Date(), prefetched?.tz ?? await getSchoolTimezone(schoolId));

  const minutesByStudent = new Map<string, number>();
  const parentComments: TeacherParentComment[] = [];
  const feelingCounts = new Map<string, number>();
  const recentReading: TeacherRecentReading[] = [];
  try {
    // Same `date >= startOfWeek` window the shared prefetch uses.
    const weekDocs = prefetched?.docs ?? (await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get()).docs;
    for (const doc of weekDocs) {
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

  const tz = await getSchoolTimezone(schoolId);
  const span = weeks * 7;
  const todayStr = localDateString(new Date(), tz);
  const startStr = shiftDateStr(todayStr, -(span - 1));
  const start = zonedDayStart(startStr, tz);

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
      const key = localDateString(when, tz);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }
  } catch { /* ignore */ }

  // Emit every school-local day in the window (including zero-count days) so
  // the heatmap grid is complete and weekday-aligned in the component.
  const out: ReadingCalendarDay[] = [];
  for (let ds = startStr; ds <= todayStr; ds = shiftDateStr(ds, 1)) {
    out.push({ date: ds, count: counts.get(ds) ?? 0 });
  }
  return out;
}
