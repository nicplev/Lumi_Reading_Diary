import { PageHeader } from "@/components/layout/page-header";
import { listAllClasses } from "@/lib/firestore/classes";
import { listAllUsers } from "@/lib/firestore/school-users";
import { ClassesTable } from "./classes-table";

export default async function ClassesPage() {
  const [classes, users] = await Promise.all([
    listAllClasses(),
    listAllUsers(),
  ]);

  return (
    <>
      <PageHeader
        title="Classes"
        description="All classes across schools"
      />
      <ClassesTable classes={classes} users={users} />
    </>
  );
}
