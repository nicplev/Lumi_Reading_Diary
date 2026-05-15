import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createClass } from "@/lib/firestore/classes";
import { createClassSchema } from "@/lib/validations/class";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId } = await params;
    const body = await request.json();
    const parsed = createClassSchema.parse(body);

    const classId = await createClass(schoolId, {
      ...parsed,
      createdBy: session.uid,
    });

    logAuditEvent({ action: "class.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "class", targetId: classId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ id: classId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create class error:", error);
    return NextResponse.json(
      { error: "Failed to create class" },
      { status: 500 }
    );
  }
}
