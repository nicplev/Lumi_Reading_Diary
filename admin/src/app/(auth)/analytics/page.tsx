import { PageHeader } from "@/components/layout/page-header";
import { getCrossSchoolAnalytics } from "@/lib/firestore/analytics";
import { CrossSchoolDashboard } from "./cross-school-dashboard";

export default async function CrossSchoolAnalyticsPage() {
  // Default to last 30 days
  const now = new Date();
  const startDate = new Date(now);
  startDate.setDate(now.getDate() - 30);
  startDate.setHours(0, 0, 0, 0);
  const endDate = new Date(now);
  endDate.setHours(23, 59, 59, 999);

  const analytics = await getCrossSchoolAnalytics({ startDate, endDate });

  return (
    <>
      <PageHeader
        title="Analytics"
        description="Cross-school overview and comparison"
      />
      <CrossSchoolDashboard initialData={analytics} />
    </>
  );
}
