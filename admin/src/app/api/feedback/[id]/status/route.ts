import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { updateFeedbackStatus } from "@/lib/firestore/feedback";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const bodySchema = z.object({
  status: z.enum(["new", "reviewed", "resolved"]),
});

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    const body = await request.json();
    const parsed = bodySchema.parse(body);

    await updateFeedbackStatus(id, parsed.status);
    await logAuditEvent({
      action: "feedback.updateStatus",
      performedBy: session.uid,
      performedByEmail: session.email,
      targetType: "feedback",
      targetId: id,
      after: { status: parsed.status },
    }).catch((auditError) =>
      console.error("Feedback status audit write failed", auditError)
    );

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: "Validation failed", details: error.issues },
        { status: 400 }
      );
    }
    console.error("Failed to update feedback status:", error);
    return NextResponse.json(
      { error: "Failed to update feedback status" },
      { status: 500 }
    );
  }
}
