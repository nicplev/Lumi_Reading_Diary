import { PageHeader } from "@/components/layout/page-header";
import { listSchoolCodes } from "@/lib/firestore/school-codes";
import { listSchools } from "@/lib/firestore/schools";
import { SchoolCodesTable } from "./school-codes-table";
import { CreateCodeDialog } from "./create-code-dialog";

export default async function SchoolCodesPage() {
  const [codes, schools] = await Promise.all([
    listSchoolCodes(),
    listSchools(),
  ]);

  return (
    <>
      <PageHeader
        title="School Codes"
        description="Manage school registration codes"
        actions={<CreateCodeDialog schools={schools} />}
      />
      <SchoolCodesTable data={codes} />
    </>
  );
}
