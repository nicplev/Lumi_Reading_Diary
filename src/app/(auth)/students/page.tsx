import { PageHeader } from "@/components/layout/page-header";
import { listAllStudents } from "@/lib/firestore/students";
import { StudentsTable } from "./students-table";

export default async function StudentsPage() {
  const students = await listAllStudents();

  return (
    <>
      <PageHeader
        title="Students"
        description="All students across schools"
      />
      <StudentsTable students={students} />
    </>
  );
}
