import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { updateClass, deactivateClass } from "@/lib/firestore/classes";
import { updateClassSchema } from "@/lib/validations/class";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; classId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, classId } = await params;
    const body = await request.json();
    const parsed = updateClassSchema.parse(body);

    await updateClass(schoolId, classId, parsed);

    logAuditEvent({ action: "class.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "class", targetId: classId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update class error:", error);
    return NextResponse.json(
      { error: "Failed to update class" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; classId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, classId } = await params;
    await deactivateClass(schoolId, classId);

    logAuditEvent({ action: "class.deactivate", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "class", targetId: classId, schoolId }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Deactivate class error:", error);
    return NextResponse.json(
      { error: "Failed to deactivate class" },
      { status: 500 }
    );
  }
}
