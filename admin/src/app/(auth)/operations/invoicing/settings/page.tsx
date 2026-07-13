import { PageHeader } from "@/components/layout/page-header";
import { getBillingEntity } from "@/lib/firestore/billing-entity";
import { BillingSettingsForm } from "./billing-settings-form";

export const dynamic = "force-dynamic";

export default async function BillingSettingsPage() {
  const entity = await getBillingEntity();
  return (
    <>
      <PageHeader
        title="Billing details"
        description="Lumi's invoicing entity — appears on every invoice"
      />
      <BillingSettingsForm entity={entity} />
    </>
  );
}
