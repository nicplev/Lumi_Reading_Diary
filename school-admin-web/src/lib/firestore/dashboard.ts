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
}

export async function getDashboardStats(schoolId: string): Promise<DashboardStats> {
  const schoolDoc = await adminDb.collection('schools').doc(schoolId).get();
  const schoolData = schoolDoc.data();

  const classesSnap = await adminDb
    .collection('schools').doc(schoolId).collection('classes')
    .where('isActive', '==', true)
    .get();

  // Count active students today
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  let activeStudentsToday = 0;
  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', today)
      .get();
    const uniqueStudents = new Set(logsSnap.docs.map(d => d.data().studentId));
    activeStudentsToday = uniqueStudents.size;
  } catch {
    // readingLogs collection may not exist yet
  }

  return {
    totalStudents: schoolData?.studentCount ?? 0,
    totalTeachers: schoolData?.teacherCount ?? 0,
    totalClasses: classesSnap.size,
    activeStudentsToday,
  };
}

export async function getWeeklyEngagement(schoolId: string): Promise<WeeklyEngagement[]> {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const today = new Date();
  const startOfWeek = new Date(today);
  startOfWeek.setDate(today.getDate() - today.getDay() + 1); // Monday
  startOfWeek.setHours(0, 0, 0, 0);

  try {
    const logsSnap = await adminDb
      .collection('schools').doc(schoolId).collection('readingLogs')
      .where('date', '>=', startOfWeek)
      .get();

    const countByDay = new Map<number, number>();
    logsSnap.docs.forEach(doc => {
      const date = doc.data().date?.toDate?.() ?? new Date();
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

    const activities: RecentActivity[] = [];
    for (const doc of logsSnap.docs) {
      const data = doc.data();
      // Try to get student name
      let studentName = 'Unknown Student';
      try {
        const studentDoc = await adminDb
          .collection('schools').doc(schoolId).collection('students').doc(data.studentId)
          .get();
        if (studentDoc.exists) {
          const s = studentDoc.data()!;
          studentName = `${s.firstName} ${s.lastName}`;
        }
      } catch { /* ignore */ }

      activities.push({
        id: doc.id,
        studentName,
        action: `Logged ${data.minutesRead ?? 0} min reading`,
        time: data.createdAt?.toDate?.() ?? new Date(),
      });
    }

    return activities;
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
