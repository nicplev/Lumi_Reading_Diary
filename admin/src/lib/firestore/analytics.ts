import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if (
    "toDate" in ts &&
    typeof (ts as { toDate: unknown }).toDate === "function"
  ) {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

// --- Types ---

export interface DateRange {
  startDate: Date;
  endDate: Date;
}

export interface EngagementMetrics {
  activeReaders: number;
  totalStudents: number;
  totalMinutes: number;
  avgMinutesPerStudent: number;
  completionRate: number;
  totalLogs: number;
}

export interface DailyReadingPoint {
  date: string;
  minutes: number;
  logCount: number;
}

export interface LevelDistributionItem {
  level: string;
  count: number;
}

export interface ClassComparisonItem {
  classId: string;
  className: string;
  studentCount: number;
  activeReaders: number;
  totalMinutes: number;
  avgMinutesPerStudent: number;
  completionRate: number;
}

export interface StudentPerformanceItem {
  studentId: string;
  firstName: string;
  lastName: string;
  classId: string;
  totalMinutes: number;
  logCount: number;
  currentStreak: number;
  currentReadingLevel?: string;
}

export interface SchoolAnalyticsData {
  engagement: EngagementMetrics;
  readingTrend: DailyReadingPoint[];
  levelDistribution: LevelDistributionItem[];
  classComparison: ClassComparisonItem[];
  topPerformers: StudentPerformanceItem[];
  needsSupport: StudentPerformanceItem[];
}

export interface CrossSchoolOverview {
  totalActiveSchools: number;
  totalStudents: number;
  totalMinutesRead: number;
  totalParents: number;
}

export interface SchoolComparisonItem {
  schoolId: string;
  schoolName: string;
  studentCount: number;
  activeReaders: number;
  totalMinutes: number;
  avgMinutesPerStudent: number;
  completionRate: number;
  parentLinkRate: number;
}

export interface OnboardingFunnelItem {
  stage: string;
  count: number;
}

export interface GrowthPoint {
  date: string;
  newSchools: number;
  newStudents: number;
  newParents: number;
}

export interface CrossSchoolAnalyticsData {
  overview: CrossSchoolOverview;
  schoolComparison: SchoolComparisonItem[];
  onboardingFunnel: OnboardingFunnelItem[];
  growthTrends: GrowthPoint[];
}

// --- Internal: fetch raw reading logs for a school in a date range ---

interface RawLogEntry {
  studentId: string;
  classId?: string;
  minutesRead: number;
  status: string;
  date: string;
}

async function fetchSchoolLogs(
  schoolId: string,
  range: DateRange
): Promise<RawLogEntry[]> {
  const snapshot = await getAdminDb()
    .collection("schools")
    .doc(schoolId)
    .collection("readingLogs")
    .where("date", ">=", Timestamp.fromDate(range.startDate))
    .where("date", "<=", Timestamp.fromDate(range.endDate))
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data();
    return {
      studentId: data.studentId,
      classId: data.classId,
      minutesRead: data.minutesRead ?? 0,
      status: data.status ?? "pending",
      date: toISO(data.date).split("T")[0],
    };
  });
}

// --- School-level analytics ---

export async function getSchoolAnalytics(
  schoolId: string,
  range: DateRange
): Promise<SchoolAnalyticsData> {
  const db = getAdminDb();
  const schoolRef = db.collection("schools").doc(schoolId);

  // Parallel fetches: logs + students + classes
  const [logs, studentsSnap, classesSnap] = await Promise.all([
    fetchSchoolLogs(schoolId, range),
    schoolRef.collection("students").where("isActive", "==", true).get(),
    schoolRef.collection("classes").get(),
  ]);

  const students = studentsSnap.docs.map((doc) => {
    const d = doc.data();
    return {
      id: doc.id,
      firstName: d.firstName as string,
      lastName: d.lastName as string,
      classId: d.classId as string,
      currentReadingLevel: d.currentReadingLevel as string | undefined,
      currentStreak: (d.stats?.currentStreak as number) ?? 0,
    };
  });

  const classMap = new Map(
    classesSnap.docs.map((doc) => [doc.id, doc.data().name as string])
  );

  // --- Engagement ---
  const activeStudentIds = new Set(logs.map((l) => l.studentId));
  const completedLogs = logs.filter((l) => l.status === "completed").length;
  const totalMinutes = logs.reduce((sum, l) => sum + l.minutesRead, 0);
  const activeReaders = activeStudentIds.size;

  const engagement: EngagementMetrics = {
    activeReaders,
    totalStudents: students.length,
    totalMinutes,
    avgMinutesPerStudent: activeReaders > 0 ? Math.round(totalMinutes / activeReaders) : 0,
    completionRate: logs.length > 0 ? completedLogs / logs.length : 0,
    totalLogs: logs.length,
  };

  // --- Reading trend (daily) ---
  const dailyMap = new Map<string, { minutes: number; count: number }>();
  for (const log of logs) {
    if (!log.date) continue;
    const existing = dailyMap.get(log.date) ?? { minutes: 0, count: 0 };
    existing.minutes += log.minutesRead;
    existing.count += 1;
    dailyMap.set(log.date, existing);
  }
  const readingTrend: DailyReadingPoint[] = Array.from(dailyMap.entries())
    .map(([date, { minutes, count }]) => ({ date, minutes, logCount: count }))
    .sort((a, b) => a.date.localeCompare(b.date));

  // --- Level distribution ---
  const levelMap = new Map<string, number>();
  for (const s of students) {
    const level = s.currentReadingLevel ?? "Unassigned";
    levelMap.set(level, (levelMap.get(level) ?? 0) + 1);
  }
  const levelDistribution: LevelDistributionItem[] = Array.from(
    levelMap.entries()
  ).map(([level, count]) => ({ level, count }));

  // --- Class comparison ---
  const classStats = new Map<
    string,
    { students: number; readers: Set<string>; minutes: number; completed: number; total: number }
  >();
  for (const s of students) {
    const cs = classStats.get(s.classId) ?? {
      students: 0,
      readers: new Set<string>(),
      minutes: 0,
      completed: 0,
      total: 0,
    };
    cs.students += 1;
    classStats.set(s.classId, cs);
  }
  for (const log of logs) {
    const cid = log.classId;
    if (!cid) continue;
    const cs = classStats.get(cid) ?? {
      students: 0,
      readers: new Set<string>(),
      minutes: 0,
      completed: 0,
      total: 0,
    };
    cs.readers.add(log.studentId);
    cs.minutes += log.minutesRead;
    cs.total += 1;
    if (log.status === "completed") cs.completed += 1;
    classStats.set(cid, cs);
  }
  const classComparison: ClassComparisonItem[] = Array.from(
    classStats.entries()
  )
    .map(([classId, cs]) => ({
      classId,
      className: classMap.get(classId) ?? classId,
      studentCount: cs.students,
      activeReaders: cs.readers.size,
      totalMinutes: cs.minutes,
      avgMinutesPerStudent:
        cs.readers.size > 0 ? Math.round(cs.minutes / cs.readers.size) : 0,
      completionRate: cs.total > 0 ? cs.completed / cs.total : 0,
    }))
    .sort((a, b) => b.totalMinutes - a.totalMinutes);

  // --- Student performance ---
  const studentLogStats = new Map<
    string,
    { minutes: number; count: number }
  >();
  for (const log of logs) {
    const existing = studentLogStats.get(log.studentId) ?? {
      minutes: 0,
      count: 0,
    };
    existing.minutes += log.minutesRead;
    existing.count += 1;
    studentLogStats.set(log.studentId, existing);
  }

  const studentPerf: StudentPerformanceItem[] = students.map((s) => {
    const stats = studentLogStats.get(s.id) ?? { minutes: 0, count: 0 };
    return {
      studentId: s.id,
      firstName: s.firstName,
      lastName: s.lastName,
      classId: s.classId,
      totalMinutes: stats.minutes,
      logCount: stats.count,
      currentStreak: s.currentStreak,
      currentReadingLevel: s.currentReadingLevel,
    };
  });

  const topPerformers = [...studentPerf]
    .sort((a, b) => b.totalMinutes - a.totalMinutes)
    .slice(0, 10);

  const needsSupport = [...studentPerf]
    .filter((s) => s.logCount > 0 || students.length <= 50)
    .sort((a, b) => a.totalMinutes - b.totalMinutes)
    .slice(0, 10);

  return {
    engagement,
    readingTrend,
    levelDistribution,
    classComparison,
    topPerformers,
    needsSupport,
  };
}

// --- Cross-school analytics ---

export async function getCrossSchoolAnalytics(
  range: DateRange
): Promise<CrossSchoolAnalyticsData> {
  const db = getAdminDb();

  const [schoolsSnap, onboardingSnap] = await Promise.all([
    db.collection("schools").get(),
    db.collection("schoolOnboarding").get(),
  ]);

  let totalStudents = 0;
  let totalParents = 0;
  let totalMinutesRead = 0;
  let totalActiveSchools = 0;

  const schoolComparison: SchoolComparisonItem[] = [];

  // Growth tracking
  const monthlyGrowth = new Map<
    string,
    { schools: number; students: number; parents: number }
  >();

  await Promise.all(
    schoolsSnap.docs.map(async (schoolDoc) => {
      const schoolData = schoolDoc.data();
      const schoolId = schoolDoc.id;
      const schoolName = (schoolData.name as string) ?? schoolId;
      const isActive = schoolData.isActive ?? true;

      if (isActive) totalActiveSchools += 1;

      // Growth: count by createdAt month
      const createdMonth = toISO(schoolData.createdAt).slice(0, 7);
      if (createdMonth) {
        const mg = monthlyGrowth.get(createdMonth) ?? {
          schools: 0,
          students: 0,
          parents: 0,
        };
        mg.schools += 1;
        monthlyGrowth.set(createdMonth, mg);
      }

      // Fetch students, parents, logs in parallel
      const [studentsSnap, parentsSnap, logs] = await Promise.all([
        schoolDoc.ref
          .collection("students")
          .where("isActive", "==", true)
          .get(),
        schoolDoc.ref.collection("parents").get(),
        fetchSchoolLogs(schoolId, range),
      ]);

      const studentCount = studentsSnap.size;
      const parentCount = parentsSnap.size;
      totalStudents += studentCount;
      totalParents += parentCount;

      // Student growth
      for (const sDoc of studentsSnap.docs) {
        const cm = toISO(sDoc.data().createdAt).slice(0, 7);
        if (cm) {
          const mg = monthlyGrowth.get(cm) ?? {
            schools: 0,
            students: 0,
            parents: 0,
          };
          mg.students += 1;
          monthlyGrowth.set(cm, mg);
        }
      }
      for (const pDoc of parentsSnap.docs) {
        const cm = toISO(pDoc.data().createdAt).slice(0, 7);
        if (cm) {
          const mg = monthlyGrowth.get(cm) ?? {
            schools: 0,
            students: 0,
            parents: 0,
          };
          mg.parents += 1;
          monthlyGrowth.set(cm, mg);
        }
      }

      // Aggregate logs
      const activeReaderIds = new Set(logs.map((l) => l.studentId));
      const schoolMinutes = logs.reduce((s, l) => s + l.minutesRead, 0);
      const completed = logs.filter((l) => l.status === "completed").length;
      totalMinutesRead += schoolMinutes;

      // Parent link rate
      let linkedStudents = 0;
      for (const sDoc of studentsSnap.docs) {
        const parentIds = (sDoc.data().parentIds as string[]) ?? [];
        if (parentIds.length > 0) linkedStudents += 1;
      }

      if (isActive) {
        schoolComparison.push({
          schoolId,
          schoolName,
          studentCount,
          activeReaders: activeReaderIds.size,
          totalMinutes: schoolMinutes,
          avgMinutesPerStudent:
            activeReaderIds.size > 0
              ? Math.round(schoolMinutes / activeReaderIds.size)
              : 0,
          completionRate:
            logs.length > 0 ? completed / logs.length : 0,
          parentLinkRate:
            studentCount > 0 ? linkedStudents / studentCount : 0,
        });
      }
    })
  );

  schoolComparison.sort((a, b) => b.totalMinutes - a.totalMinutes);

  // Onboarding funnel
  const funnelCounts = new Map<string, number>();
  const stages = [
    "demo",
    "interested",
    "registered",
    "setupInProgress",
    "active",
    "suspended",
  ];
  for (const stage of stages) {
    funnelCounts.set(stage, 0);
  }
  for (const doc of onboardingSnap.docs) {
    const status = (doc.data().status as string) ?? "demo";
    funnelCounts.set(status, (funnelCounts.get(status) ?? 0) + 1);
  }
  const onboardingFunnel: OnboardingFunnelItem[] = stages.map((stage) => ({
    stage,
    count: funnelCounts.get(stage) ?? 0,
  }));

  // Growth trends
  const growthTrends: GrowthPoint[] = Array.from(monthlyGrowth.entries())
    .map(([date, g]) => ({
      date,
      newSchools: g.schools,
      newStudents: g.students,
      newParents: g.parents,
    }))
    .sort((a, b) => a.date.localeCompare(b.date))
    .slice(-12);

  return {
    overview: {
      totalActiveSchools,
      totalStudents,
      totalMinutesRead,
      totalParents,
    },
    schoolComparison,
    onboardingFunnel,
    growthTrends,
  };
}
