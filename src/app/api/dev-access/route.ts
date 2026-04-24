import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import {
  addDevAccessEmail,
  listDevAccessEmails,
} from "@/lib/firestore/dev-access";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const addSchema = z.object({
  email: z.string().email("A valid email is required").trim().toLowerCase(),
  note: z.string().trim().max(200).optional(),
});

export async function GET() {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const emails = await listDevAccessEmails();
  return NextResponse.json({ emails });
}

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = addSchema.parse(body);

    const created = await addDevAccessEmail({
      email: parsed.email,
      addedBy: session.uid,
      addedByEmail: session.email ?? undefined,
      note: parsed.note,
    });

    logAuditEvent({
      action: "devAccess.grant",
      performedBy: session.uid,
      performedByEmail: session.email ?? undefined,
      targetType: "devAccessEmail",
      targetId: created.id,
      after: { email: created.email, note: created.note },
    }).catch(console.error);

    return NextResponse.json(created, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof z.ZodError) {
      return NextResponse.json(
        { error: error.issues[0]?.message ?? "Validation failed" },
        { status: 400 }
      );
    }
    const message =
      error instanceof Error ? error.message : "Failed to add dev access";
    // "already has dev access" → 409 so the client can show the right toast.
    const status = /already has dev access/i.test(message) ? 409 : 500;
    if (status === 500) console.error("Add dev access error:", error);
    return NextResponse.json({ error: message }, { status });
  }
}
