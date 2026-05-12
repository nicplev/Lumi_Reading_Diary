import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { updateStudent, deactivateStudent } from "@/lib/firestore/students";
import { updateStudentSchema } from "@/lib/validations/student";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; studentId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, studentId } = await params;
    const body = await request.json();
    const parsed = updateStudentSchema.parse(body);

    await updateStudent(schoolId, studentId, parsed);

    logAuditEvent({ action: "student.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "student", targetId: studentId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update student error:", error);
    return NextResponse.json(
      { error: "Failed to update student" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; studentId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, studentId } = await params;
    await deactivateStudent(schoolId, studentId);

    logAuditEvent({ action: "student.deactivate", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "student", targetId: studentId, schoolId }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Deactivate student error:", error);
    return NextResponse.json(
      { error: "Failed to deactivate student" },
      { status: 500 }
    );
  }
}
