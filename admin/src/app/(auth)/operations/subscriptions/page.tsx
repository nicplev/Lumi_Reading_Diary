import { PageHeader } from "@/components/layout/page-header";
import { listSchools } from "@/lib/firestore/schools";
import {
  getCurrentAcademicYear,
  listSubscriptionsForYear,
} from "@/lib/firestore/school-subscriptions";
import { isActiveSubscriptionStatus } from "@lumi/types";
import { SubscriptionsDashboard, type BillingRow } from "./subscriptions-dashboard";

export default async function SubscriptionsPage() {
  const currentAcademicYear = await getCurrentAcademicYear();
  const [schools, subs] = await Promise.all([
    listSchools(),
    listSubscriptionsForYear(currentAcademicYear),
  ]);

  const subBySchool = new Map(subs.map((s) => [s.schoolId, s]));

  const rows: BillingRow[] = schools
    .filter((s) => s.isActive)
    .map((s) => {
      const sub = subBySchool.get(s.id);
      return {
        schoolId: s.id,
        schoolName: s.name,
        studentCount: s.studentCount,
        status: sub?.status ?? null,
        tier: sub?.tier ?? null,
        amount: sub?.amount ?? null,
        invoiceRef: sub?.invoiceRef ?? null,
        accessOn: sub ? isActiveSubscriptionStatus(sub.status) : false,
      };
    });

  return (
    <>
      <PageHeader
        title="Subscriptions"
        description={`Platform billing status for ${currentAcademicYear} — who's paid`}
      />
      <SubscriptionsDashboard
        rows={rows}
        academicYear={currentAcademicYear}
      />
    </>
  );
}
