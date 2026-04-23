import { PageHeader } from "@/components/layout/page-header";
import { listSessions } from "@/lib/firestore/impersonation-audit";
import { ImpersonationAuditViewer } from "./impersonation-audit-viewer";

export default async function ImpersonationAuditPage() {
  const sessions = await listSessions({ limit: 200 });
  return (
    <>
      <PageHeader
        title="Impersonation Audit"
        description="Developer read-only impersonation sessions and every action they produced"
      />
      <ImpersonationAuditViewer initialSessions={sessions} />
    </>
  );
}
