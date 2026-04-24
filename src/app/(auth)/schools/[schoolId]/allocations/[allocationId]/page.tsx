import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { getAllocation } from "@/lib/firestore/allocations";
import { listClasses } from "@/lib/firestore/classes";
import { listSchoolUsers } from "@/lib/firestore/school-users";
import { listStudents } from "@/lib/firestore/students";
import { AllocationDetail } from "./allocation-detail";

export default async function AllocationDetailPage({
  params,
}: {
  params: Promise<{ schoolId: string; allocationId: string }>;
}) {
  const { schoolId, allocationId } = await params;

  const [school, allocation, classes, users, students] = await Promise.all([
    getSchool(schoolId),
    getAllocation(schoolId, allocationId),
    listClasses(schoolId),
    listSchoolUsers(schoolId),
    listStudents(schoolId),
  ]);

  if (!school || !allocation) notFound();

  return (
    <>
      <PageHeader
        title={`Allocation - ${allocation.templateName || allocation.type}`}
        description={`${school.name}`}
      />
      <AllocationDetail
        schoolId={schoolId}
        allocation={allocation}
        classes={classes}
        users={users}
        students={students}
      />
    </>
  );
}
