import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getDashboardStats, getWeeklyEngagement, getWeeklyClassEngagement, getRecentActivity, getTeacherDashboardData, getTeacherDashboardWidgets } from '@/lib/firestore/dashboard';
import { getSchool } from '@/lib/firestore/school';
import { AdminDashboard } from './admin-dashboard';
import { TeacherDashboard } from './teacher-dashboard';

export default async function DashboardPage() {
  const session = await getSession();
  if (!session) redirect('/login');

  const school = await getSchool(session.schoolId);

  if (session.role === 'schoolAdmin') {
    const [stats, weeklyEngagement, classSeries, recentActivity] = await Promise.all([
      getDashboardStats(session.schoolId),
      getWeeklyEngagement(session.schoolId),
      getWeeklyClassEngagement(session.schoolId),
      getRecentActivity(session.schoolId),
    ]);

    return (
      <AdminDashboard
        schoolName={school?.name ?? 'School'}
        stats={stats}
        weeklyEngagement={weeklyEngagement}
        classSeries={classSeries}
        recentActivity={recentActivity.map(a => ({
          ...a,
          time: a.time.toISOString(),
        }))}
      />
    );
  }

  // Teacher dashboard
  const [teacherData, weeklyEngagement, widgets] = await Promise.all([
    getTeacherDashboardData(session.schoolId, session.uid),
    getWeeklyEngagement(session.schoolId),
    getTeacherDashboardWidgets(session.schoolId, session.uid),
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
