import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import { BulkImport } from "./bulk-import";

export default async function BulkImportPage() {
  const schools = await listSchools();

  return (
    <>
      <PageHeader
        title="Bulk Import"
        description="Import students from CSV files"
      />
      <BulkImport schools={schools} />
    </>
  );
}
