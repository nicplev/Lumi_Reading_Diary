import { PageHeader } from "@/components/layout/page-header";
import { listAuditLogs } from "@/lib/firestore/audit-log";
import { AuditLogViewer } from "./audit-log-viewer";

export default async function AuditLogPage() {
  const logs = await listAuditLogs({ limit: 200 });

  return (
    <>
      <PageHeader
        title="Audit Log"
        description="Admin action history"
      />
      <AuditLogViewer initialLogs={logs} />
    </>
  );
}
