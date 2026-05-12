import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import {
  removeDevAccessEmail,
  updateDevAccessEmail,
} from "@/lib/firestore/dev-access";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const patchSchema = z.object({
  // `null` explicitly clears the note; `undefined` leaves it as-is.
  note: z.string().trim().max(200).nullable().optional(),
});

export async function PATCH(
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
    const parsed = patchSchema.parse(body);

    await updateDevAccessEmail(id, { note: parsed.note });

    logAuditEvent({
      action: "devAccess.update",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "devAccessEmail",
      targetId: id,
      after: { note: parsed.note },
    }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: error.issues[0]?.message ?? "Validation failed" },
        { status: 400 }
      );
    }
    console.error("Update dev access error:", error);
    return NextResponse.json(
      { error: "Failed to update dev access" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { id } = await params;
    await removeDevAccessEmail(id);

    logAuditEvent({
      action: "devAccess.revoke",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "devAccessEmail",
      targetId: id,
    }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Delete dev access error:", error);
    return NextResponse.json(
      { error: "Failed to revoke dev access" },
      { status: 500 }
    );
  }
}
