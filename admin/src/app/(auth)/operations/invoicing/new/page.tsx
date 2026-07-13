import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import { getBillingEntity } from "@/lib/firestore/billing-entity";
import { getCurrentAcademicYear } from "@/lib/firestore/school-subscriptions";
import { InvoiceBuilder } from "./invoice-builder";

export const dynamic = "force-dynamic";

export default async function NewInvoicePage({
  searchParams,
}: {
  searchParams: Promise<{ schoolId?: string; year?: string }>;
}) {
  const sp = await searchParams;
  const [schools, entity, currentYear] = await Promise.all([
    listSchools(),
    getBillingEntity(),
    getCurrentAcademicYear(),
  ]);
  const schoolOptions = schools
    .filter((s) => s.isActive)
    .map((s) => ({ id: s.id, name: s.name, studentCount: s.studentCount ?? 0 }));

  return (
    <>
      <PageHeader title="New invoice" description="Create a Lumi-branded invoice" />
      <InvoiceBuilder
        schools={schoolOptions}
        entity={entity}
        currentYear={currentYear}
        preselectSchoolId={sp.schoolId}
        preselectYear={sp.year ? Number(sp.year) : undefined}
      />
    </>
  );
}
