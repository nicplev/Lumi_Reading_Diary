import { PageHeader } from "@/components/layout/page-header";
import { getDashboardData } from "@/lib/firestore/dashboard";
import { DashboardClient } from "@/components/dashboard/dashboard-client";

// The RSC render supplies initialData (no blank first paint); the client
// component then polls /api/dashboard for live updates.
export const dynamic = "force-dynamic";

export default async function DashboardPage() {
  const initialData = await getDashboardData();

  return (
    <>
      <PageHeader
        title="Dashboard"
        description="Live overview of the Lumi platform"
      />
      <DashboardClient initialData={initialData} />
    </>
  );
}
