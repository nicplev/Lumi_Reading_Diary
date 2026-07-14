import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { createInvoice, listInvoices } from "@/lib/firestore/invoices";
import { createInvoiceSchema } from "@/lib/validations/invoice";
import { logAuditEvent } from "@/lib/firestore/audit-log";
import type { InvoiceStatus } from "@lumi/types";

// GET /api/invoicing?schoolId=&status=  -> invoice register (all, or filtered)
export async function GET(request: Request) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { searchParams } = new URL(request.url);
  const schoolId = searchParams.get("schoolId") || undefined;
  const status = (searchParams.get("status") as InvoiceStatus | null) || undefined;
  const invoices = await listInvoices({ schoolId, status });
  return NextResponse.json({ invoices });
}

// POST /api/invoicing  -> create + number an invoice (totals computed server-side)
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const body = await request.json();
    const parsed = createInvoiceSchema.parse(body);
    const invoice = await createInvoice({ ...parsed, createdBy: session.uid });
    logAuditEvent({
      action: "invoice.create",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "invoice",
      targetId: invoice.id,
      schoolId: parsed.schoolId,
      after: {
        invoiceNumber: invoice.invoiceNumber,
        total: invoice.total,
        status: invoice.status,
      },
    }).catch(console.error);
    return NextResponse.json({ invoice });
  } catch (err) {
    if (err instanceof z.ZodError)
      return NextResponse.json(
        { error: "Invalid input", details: err.issues },
        { status: 400 }
      );
    console.error("invoice POST error:", err);
    return NextResponse.json(
      { error: "Failed to create invoice" },
      { status: 500 }
    );
  }
}
