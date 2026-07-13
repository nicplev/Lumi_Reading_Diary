import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import {
  getBillingEntity,
  setBillingEntity,
} from "@/lib/firestore/billing-entity";
import { billingEntitySchema } from "@/lib/validations/invoice";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function GET() {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const entity = await getBillingEntity();
  return NextResponse.json(entity);
}

export async function PUT(request: Request) {
  const session = await verifySession();
  if (!session)
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  try {
    const body = await request.json();
    const parsed = billingEntitySchema.parse(body);
    await setBillingEntity({ ...parsed, updatedBy: session.uid });
    logAuditEvent({
      action: "billingEntity.update",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "config",
      targetId: "billingEntity",
      after: parsed as Record<string, unknown>,
    }).catch(console.error);
    return NextResponse.json({ success: true });
  } catch (err) {
    if (err instanceof z.ZodError)
      return NextResponse.json(
        { error: "Invalid input", details: err.issues },
        { status: 400 }
      );
    console.error("billing-entity PUT error:", err);
    return NextResponse.json(
      { error: "Failed to save billing details" },
      { status: 500 }
    );
  }
}
