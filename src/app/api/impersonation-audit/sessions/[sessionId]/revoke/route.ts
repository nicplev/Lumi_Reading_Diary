import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { revokeSession } from "@/lib/firestore/impersonation-audit";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const bodySchema = z.object({
  reason: z.string().trim().min(5, "Reason must be at least 5 characters."),
});

export async function POST(
  request: Request,
  { params }: { params: Promise<{ sessionId: string }> },
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const { sessionId } = await params;

  let parsed;
  try {
    parsed = bodySchema.parse(await request.json());
  } catch (error) {
    const message =
      error instanceof z.ZodError
        ? (error.issues[0]?.message ?? "Invalid request body")
        : "Invalid request body";
    return NextResponse.json({ error: message }, { status: 400 });
  }

  try {
    const updated = await revokeSession({
      sessionId,
      reason: parsed.reason,
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
    });

    logAuditEvent({
      action: "impersonation.revoke",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "impersonationSession",
      targetId: sessionId,
      metadata: { reason: parsed.reason },
    }).catch(console.error);

    return NextResponse.json({ session: updated });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Revoke failed.";
    const status = /not found/i.test(message)
      ? 404
      : /not active/i.test(message)
        ? 409
        : 500;
    if (status === 500) console.error("Impersonation revoke error:", error);
    return NextResponse.json({ error: message }, { status });
  }
}
