import { PageHeader } from "@/components/layout/page-header";
import { listAuditLogs } from "@/lib/firestore/audit-log";
import { AuditLogViewer } from "./audit-log-viewer";

export default async function AuditLogPage({
  searchParams,
}: {
  searchParams: Promise<{ event?: string }>;
}) {
  const { event } = await searchParams;
  const logs = await listAuditLogs({ limit: 200 });
  const initialEventId = logs.some((log) => log.id === event) ? event : undefined;

  return (
    <>
      <PageHeader
        title="Audit Log"
        description="Admin action history"
      />
      <AuditLogViewer initialLogs={logs} initialEventId={initialEventId} />
    </>
  );
}
