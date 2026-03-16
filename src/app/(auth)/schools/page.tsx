import Link from "next/link";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import { SchoolsTable } from "./schools-table";

export default async function SchoolsPage() {
  const schools = await listSchools();

  return (
    <>
      <PageHeader
        title="Schools"
        description="Manage all schools on the platform"
        actions={
          <Button render={<Link href="/schools/new" />}>
            <Plus className="mr-2 h-4 w-4" />
            Add School
          </Button>
        }
      />
      <SchoolsTable data={schools} />
    </>
  );
}
