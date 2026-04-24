import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { listAllocations } from "@/lib/firestore/allocations";
import { listClasses } from "@/lib/firestore/classes";
import { listSchoolUsers } from "@/lib/firestore/school-users";
import { listStudents } from "@/lib/firestore/students";
import { AllocationsList } from "./allocations-list";

export default async function AllocationsPage({
  params,
}: {
  params: Promise<{ schoolId: string }>;
}) {
  const { schoolId } = await params;

  const [school, allocations, classes, users, students] = await Promise.all([
    getSchool(schoolId),
    listAllocations(schoolId),
    listClasses(schoolId),
    listSchoolUsers(schoolId),
    listStudents(schoolId),
  ]);

  if (!school) notFound();

  return (
    <>
      <PageHeader
        title={`${school.name} - Allocations`}
        description={`${allocations.length} allocations`}
      />
      <AllocationsList
        schoolId={schoolId}
        allocations={allocations}
        classes={classes}
        users={users}
        students={students}
      />
    </>
  );
}
