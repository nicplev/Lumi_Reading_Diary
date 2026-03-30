import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getDashboardStats, getWeeklyEngagement, getRecentActivity, getTeacherDashboardData } from '@/lib/firestore/dashboard';
import { getSchool } from '@/lib/firestore/school';
import { AdminDashboard } from './admin-dashboard';
import { TeacherDashboard } from './teacher-dashboard';

export default async function DashboardPage() {
  const session = await getSession();
  if (!session) redirect('/login');

  const school = await getSchool(session.schoolId);

  if (session.role === 'schoolAdmin') {
    const [stats, weeklyEngagement, recentActivity] = await Promise.all([
      getDashboardStats(session.schoolId),
      getWeeklyEngagement(session.schoolId),
      getRecentActivity(session.schoolId),
    ]);

    return (
      <AdminDashboard
        schoolName={school?.name ?? 'School'}
        stats={stats}
        weeklyEngagement={weeklyEngagement}
        recentActivity={recentActivity.map(a => ({
          ...a,
          time: a.time.toISOString(),
        }))}
      />
    );
  }

  // Teacher dashboard
  const [teacherData, weeklyEngagement] = await Promise.all([
    getTeacherDashboardData(session.schoolId, session.uid),
    getWeeklyEngagement(session.schoolId),
  ]);

  return (
    <TeacherDashboard
      userName={session.fullName}
      data={teacherData}
      weeklyEngagement={weeklyEngagement}
    />
  );
}
