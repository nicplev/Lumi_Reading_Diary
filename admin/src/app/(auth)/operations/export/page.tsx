import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import { ExportTool } from "./export-tool";

export default async function ExportPage() {
  const schools = await listSchools();

  return (
    <>
      <PageHeader
        title="Export Data"
        description="Download school data as CSV files"
      />
      <ExportTool schools={schools} />
    </>
  );
}
