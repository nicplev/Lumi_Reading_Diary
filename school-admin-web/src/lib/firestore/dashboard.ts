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
