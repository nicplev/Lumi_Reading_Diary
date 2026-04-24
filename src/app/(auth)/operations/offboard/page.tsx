import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import { OffboardWizard } from "./offboard-wizard";

export default async function OffboardPage() {
  const schools = await listSchools();

  return (
    <>
      <PageHeader
        title="Offboard School"
        description="Deactivate a school and all its data"
      />
      <OffboardWizard schools={schools} />
    </>
  );
}
