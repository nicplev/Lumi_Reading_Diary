import { PageHeader } from "@/components/layout/page-header";
import { CreateSchoolForm } from "./create-school-form";

export default function NewSchoolPage() {
  return (
    <>
      <PageHeader
        title="New School"
        description="Create a new school on the platform"
      />
      <CreateSchoolForm />
    </>
  );
}
