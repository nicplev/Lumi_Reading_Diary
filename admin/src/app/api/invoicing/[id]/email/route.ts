import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { getInvoice } from "@/lib/firestore/invoices";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const emailSchema = z.object({
  to: z.string().email(),
  subject: z.string().max(200).optional(),
  message: z.string().max(4000).optional(),
  pdfBase64: z.string().min(1),
  filename: z.string().max(120).optional(),
});

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { id } = await params;
  try {
    const invoice = await getInvoice(id);
    if (!invoice)
      return NextResponse.json({ error: "Invoice not found" }, { status: 404 });

    const body = await request.json();
    const parsed = emailSchema.parse(body);

    // Queue doc — the processInvoiceEmail Cloud Function sends it with the
    // attached PDF via SendGrid.
    await getAdminDb().collection("invoiceEmails").add({
      invoiceId: id,
      to: parsed.to,
      subject: parsed.subject ?? `Invoice ${invoice.invoiceNumber} from Lumi`,
      message: parsed.message ?? null,
      pdfBase64: parsed.pdfBase64,
      filename: parsed.filename ?? `${invoice.invoiceNumber || "invoice"}.pdf`,
      status: "queued",
      createdBy: session.uid,
      createdAt: FieldValue.serverTimestamp(),
    });

    logAuditEvent({
      action: "invoice.email",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "invoice",
      targetId: id,
      metadata: { to: parsed.to },
    }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (err) {
    if (err instanceof z.ZodError)
      return NextResponse.json(
        { error: "Invalid input", details: err.issues },
        { status: 400 }
      );
    console.error("invoice email error:", err);
    return NextResponse.json(
      { error: "Failed to queue invoice email" },
      { status: 500 }
    );
  }
}
