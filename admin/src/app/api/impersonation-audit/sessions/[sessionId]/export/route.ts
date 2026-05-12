import { verifySession } from "@/lib/auth";
import { exportSessionAsCsv } from "@/lib/firestore/impersonation-audit";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ sessionId: string }> },
) {
  const session = await verifySession();
  if (!session) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }
  const { sessionId } = await params;

  try {
    const csv = await exportSessionAsCsv({
      sessionId,
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
    });

    logAuditEvent({
      action: "impersonation.export",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "impersonationSession",
      targetId: sessionId,
    }).catch(console.error);

    return new Response(csv, {
      status: 200,
      headers: {
        "content-type": "text/csv; charset=utf-8",
        "content-disposition": `attachment; filename="impersonation-${sessionId}.csv"`,
        "cache-control": "no-store",
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Export failed.";
    const status = /not found/i.test(message) ? 404 : 500;
    if (status === 500) console.error("Impersonation export error:", error);
    return new Response(JSON.stringify({ error: message }), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}
