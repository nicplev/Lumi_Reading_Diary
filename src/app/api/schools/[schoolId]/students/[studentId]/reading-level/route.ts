import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { updateReadingLevel } from "@/lib/firestore/students";
import { updateReadingLevelSchema } from "@/lib/validations/student";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(
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
    const parsed = updateReadingLevelSchema.parse(body);

    await updateReadingLevel(schoolId, studentId, {
      level: parsed.level,
      levelIndex: parsed.levelIndex,
      reason: parsed.reason,
      source: parsed.source,
      changedByUserId: session.uid,
      changedByName: session.name ?? "Admin",
    });

    logAuditEvent({ action: "student.updateLevel", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "student", targetId: studentId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update reading level error:", error);
    return NextResponse.json(
      { error: "Failed to update reading level" },
      { status: 500 }
    );
  }
}
