import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool, getSchoolStats } from "@/lib/firestore/schools";
import { SchoolDetailTabs } from "./school-detail-tabs";

export default async function SchoolDetailPage({
  params,
}: {
  params: Promise<{ schoolId: string }>;
}) {
  const { schoolId } = await params;
  const [school, stats] = await Promise.all([
    getSchool(schoolId),
    getSchoolStats(schoolId),
  ]);

  if (!school) notFound();

  return (
    <>
      <PageHeader
        title={school.name}
        description={school.contactEmail || undefined}
      />
      <SchoolDetailTabs school={school} stats={stats} />
    </>
  );
}
