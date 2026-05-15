import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { callDeployedCallable } from "@/lib/callDeployedCallable";
import { getSession } from "@/lib/firestore/impersonation-audit";

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
    // Pre-check to preserve the original 404 / 409 status codes — the deployed
    // callable returns the same wire shape on already-non-active sessions
    // (`{sessionId, status}`, HTTP 200) as on a successful revoke, so we'd
    // lose that distinction without an existence + status check here.
    const existing = await getSession(sessionId);
    if (!existing) {
      return NextResponse.json({ error: "Session not found." }, { status: 404 });
    }
    if (existing.status !== "active") {
      return NextResponse.json(
        { error: `Session is ${existing.status}, not active.` },
        { status: 409 },
      );
    }

    await callDeployedCallable<{ sessionId: string; status: string }>(
      "revokeImpersonationSession",
      session.uid,
      { sessionId, reason: parsed.reason },
    );

    // Re-read the session so the response shape matches the previous local
    // fork (caller expects the full ImpersonationSession in `session`).
    const updated = await getSession(sessionId);
    return NextResponse.json({ session: updated });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Revoke failed.";
    const httpStatus =
      typeof (error as { httpStatus?: number })?.httpStatus === "number"
        ? (error as { httpStatus: number }).httpStatus
        : 500;
    if (httpStatus === 500) {
      console.error("Impersonation revoke (callable) error:", error);
    }
    return NextResponse.json({ error: message }, { status: httpStatus });
  }
}
