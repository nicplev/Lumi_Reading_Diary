import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getInvoice, updateInvoiceStatus } from "@/lib/firestore/invoices";
import { updateInvoiceStatusSchema } from "@/lib/validations/invoice";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import type { InvoiceStatus } from "@lumi/types";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { id } = await params;
  const invoice = await getInvoice(id);
  if (!invoice)
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ invoice });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { id } = await params;
  try {
    const body = await request.json();
    const { status } = updateInvoiceStatusSchema.parse(body);
    await updateInvoiceStatus(id, status as InvoiceStatus, session.uid);
    logAuditEvent({
      action: "invoice.statusUpdate",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "invoice",
      targetId: id,
      after: { status },
    }).catch(console.error);
    return NextResponse.json({ success: true });
  } catch (err) {
    if (err instanceof z.ZodError)
      return NextResponse.json(
        { error: "Invalid input", details: err.issues },
        { status: 400 }
      );
    console.error("invoice PATCH error:", err);
    return NextResponse.json(
      { error: "Failed to update invoice" },
      { status: 500 }
    );
  }
}
