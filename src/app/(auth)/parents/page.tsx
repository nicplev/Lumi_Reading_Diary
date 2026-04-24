import { PageHeader } from "@/components/layout/page-header";
import { listAllParents } from "@/lib/firestore/parents";
import { ParentsTable } from "./parents-table";

export default async function ParentsPage() {
  const parents = await listAllParents();

  return (
    <>
      <PageHeader
        title="Parents"
        description="All parents across schools"
      />
      <ParentsTable parents={parents} />
    </>
  );
}
