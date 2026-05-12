import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { resolveDeletionRequest } from "@/lib/firestore/community-books";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import { z } from "zod";

const resolveSchema = z.object({
  isbn: z.string().min(1, "ISBN is required"),
  action: z.enum(["approved", "rejected"]),
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
    const parsed = resolveSchema.parse(body);

    await resolveDeletionRequest(
      parsed.isbn,
      id,
      parsed.action,
      session.uid
    );

    logAuditEvent({
      action: `community_book_deletion_${parsed.action}`,
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "community_book",
      targetId: parsed.isbn,
      metadata: { requestId: id, action: parsed.action },
    }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        {
          error: "Validation failed",
          details: (error as unknown as { errors: unknown }).errors,
        },
        { status: 400 }
      );
    }
    console.error("Error resolving deletion request:", error);
    return NextResponse.json(
      { error: "Failed to resolve deletion request" },
      { status: 500 }
    );
  }
}
