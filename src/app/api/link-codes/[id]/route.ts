import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { revokeLinkCode } from "@/lib/firestore/link-codes";
import { logAuditEvent } from "@/lib/firestore/audit-log";

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
    await revokeLinkCode(id, session.uid);

    logAuditEvent({ action: "linkCode.revoke", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "linkCode", targetId: id }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Revoke link code error:", error);
    return NextResponse.json(
      { error: "Failed to revoke link code" },
      { status: 500 }
    );
  }
}
