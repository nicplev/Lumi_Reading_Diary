import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import {
  getSession,
  listEvents,
} from "@/lib/firestore/impersonation-audit";
import { SessionDetailView } from "./session-detail-view";

export default async function ImpersonationSessionPage({
  params,
}: {
  params: Promise<{ sessionId: string }>;
}) {
  const { sessionId } = await params;
  const session = await getSession(sessionId);
  if (!session) notFound();
  const events = await listEvents(sessionId);

  return (
    <>
      <PageHeader
        title="Impersonation Session"
        description="Full chronological trail of a developer read-only session"
      />
      <SessionDetailView initialSession={session} initialEvents={events} />
    </>
  );
}
