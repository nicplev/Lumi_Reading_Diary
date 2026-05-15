import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { getSchoolAnalytics } from "@/lib/firestore/analytics";
import { SchoolAnalyticsDashboard } from "./school-analytics-dashboard";

export default async function SchoolAnalyticsPage({
  params,
}: {
  params: Promise<{ schoolId: string }>;
}) {
  const { schoolId } = await params;

  // Default to this week
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(now.getDate() - now.getDay());
  startDate.setHours(0, 0, 0, 0);
  const endDate = new Date(now);
  endDate.setHours(23, 59, 59, 999);

  const [school, analytics] = await Promise.all([
    getSchool(schoolId),
    getSchoolAnalytics(schoolId, { startDate, endDate }),
  ]);

  if (!school) notFound();

  return (
    <>
      <PageHeader
        title={`${school.name} - Analytics`}
        description="School engagement and reading data"
      />
      <SchoolAnalyticsDashboard
        schoolId={schoolId}
        initialData={analytics}
      />
    </>
  );
}
