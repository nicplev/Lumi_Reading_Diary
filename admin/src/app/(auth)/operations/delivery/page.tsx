import { PageHeader } from "@/components/layout/page-header";
import { listDeliveryIncidents } from "@/lib/firestore/delivery-incidents";
import { DeliveryIncidentsTable } from "./delivery-incidents-table";

export const dynamic = "force-dynamic";

export default async function DeliveryIncidentsPage({
  searchParams,
}: {
  searchParams: Promise<{ kind?: string; status?: string }>;
}) {
  const params = await searchParams;
  const incidents = await listDeliveryIncidents();
  const initialKind =
    params.kind === "onboarding" || params.kind === "notification"
      ? params.kind
      : "all";
  const initialStatus = params.status === "all" ? "all" : "open";

  return (
    <>
      <PageHeader
        title="Delivery Incidents"
        description="Review failed onboarding emails and notification campaigns across schools"
      />
      <DeliveryIncidentsTable
        incidents={incidents}
        initialKind={initialKind}
        initialStatus={initialStatus}
      />
    </>
  );
}
