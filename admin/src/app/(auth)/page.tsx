import { School, Users, BookOpen, ClipboardList } from "lucide-react";
import { type ColumnDef } from "@tanstack/react-table";
import { getSchoolCount } from "@/lib/firestore/schools";
import { getStudentCount } from "@/lib/firestore/students";
import {
  getReadingLogStats,
  getRecentActivity,
  type RecentActivity,
} from "@/lib/firestore/reading-logs";
import { getOnboardingCount } from "@/lib/firestore/onboarding";
import { PageHeader } from "@/components/layout/page-header";
import { StatCard } from "@/components/cards/stat-card";
import { RecentActivityTable } from "./recent-activity-table";

export default async function DashboardPage() {
  const [schoolCount, studentCount, logStats, onboardingCount, recentActivity] =
    await Promise.all([
      getSchoolCount(),
      getStudentCount(),
      getReadingLogStats(),
      getOnboardingCount(),
      getRecentActivity(20),
    ]);

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Overview of your Lumi reading tracker platform"
      />

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
        <StatCard
          title="Total Schools"
          value={schoolCount}
          icon={School}
          description="Active schools"
        />
        <StatCard
          title="Total Students"
          value={studentCount}
          icon={Users}
          description="Active students"
        />
        <StatCard
          title="Reading Logs"
          value={logStats.thisWeek}
          icon={BookOpen}
          description={`${logStats.thisMonth} this month`}
        />
        <StatCard
          title="Onboarding"
          value={onboardingCount}
          icon={ClipboardList}
          description="Total requests"
        />
      </div>

      <div>
        <h2 className="mb-4 text-lg font-semibold">Recent Activity</h2>
        <RecentActivityTable data={recentActivity} />
      </div>
    </>
  );
}
