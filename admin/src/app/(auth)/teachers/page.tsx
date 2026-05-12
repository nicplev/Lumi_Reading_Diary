import { PageHeader } from "@/components/layout/page-header";
import { listAllUsers } from "@/lib/firestore/school-users";
import { TeachersTable } from "./teachers-table";

export default async function TeachersPage() {
  const allUsers = await listAllUsers();
  const teachers = allUsers.filter(
    (u) => u.role === "teacher" || u.role === "schoolAdmin"
  );

  return (
    <>
      <PageHeader
        title="Teachers"
        description="All teachers and school admins across schools"
      />
      <TeachersTable teachers={teachers} />
    </>
  );
}
