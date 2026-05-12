import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createStudent } from "@/lib/firestore/students";
import { createStudentSchema } from "@/lib/validations/student";
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
    const parsed = createStudentSchema.parse(body);

    const studentId = await createStudent(schoolId, parsed);

    logAuditEvent({ action: "student.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "student", targetId: studentId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ id: studentId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create student error:", error);
    return NextResponse.json(
      { error: "Failed to create student" },
      { status: 500 }
    );
  }
}
