import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getDashboardStats, getWeeklyEngagement, getWeeklyReadingSummary, getOperationalSummary, getTeacherDashboardData, getTeacherDashboardWidgets, fetchActiveClasses, fetchCurrentWeekLogs } from '@/lib/firestore/dashboard';
import { getSchool } from '@/lib/firestore/school';
import { AdminDashboard } from './admin-dashboard';
import { TeacherDashboard } from './teacher-dashboard';

export default async function DashboardPage() {
  const session = await getSession();
  if (!session) redirect('/login');

  const school = await getSchool(session.schoolId);

  if (session.role === 'schoolAdmin') {
    // Shared prefetch: getDashboardStats and getOperationalSummary both need
    // the active-classes snapshot — fetch it once.
    const classesSnap = await fetchActiveClasses(session.schoolId);
    const [stats, weekly, operational] = await Promise.all([
      getDashboardStats(session.schoolId, classesSnap),
      getWeeklyReadingSummary(session.schoolId),
      getOperationalSummary(session.schoolId, classesSnap),
    ]);

    return (
      <AdminDashboard
        schoolName={school?.name ?? 'School'}
        stats={stats}
        weekly={weekly}
        operational={operational}
      />
    );
  }

  // Teacher dashboard. One whole-school week scan shared by all three
  // functions — they previously each ran their own overlapping scan
  // (today ⊂ week ⊂ week) per render.
  const weekLogs = await fetchCurrentWeekLogs(session.schoolId);
  const [teacherData, weeklyEngagement, widgets] = await Promise.all([
    getTeacherDashboardData(session.schoolId, session.uid, weekLogs),
    getWeeklyEngagement(session.schoolId, 0, weekLogs),
    getTeacherDashboardWidgets(session.schoolId, session.uid, weekLogs),
  ]);

  return (
    <TeacherDashboard
      userName={session.fullName}
      data={teacherData}
      weeklyEngagement={weeklyEngagement}
      widgets={{
        topReaders: widgets.topReaders,
        nudges: widgets.nudges,
        parentComments: widgets.parentComments.map((c) => ({ ...c, at: c.at.toISOString() })),
        sentiment: widgets.sentiment,
        groupComparison: widgets.groupComparison,
        recentReading: widgets.recentReading.map((r) => ({ ...r, at: r.at.toISOString() })),
        recentAchievements: widgets.recentAchievements.map((a) => ({
          ...a,
          earnedAt: a.earnedAt ? a.earnedAt.toISOString() : null,
        })),
      }}
    />
  );
}
