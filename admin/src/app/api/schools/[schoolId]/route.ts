import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { updateSchool, deactivateSchool } from "@/lib/firestore/schools";
import { updateSchoolSchema } from "@/lib/validations/school";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
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
    const parsed = updateSchoolSchema.parse(body);

    await updateSchool(schoolId, parsed);
    logAuditEvent({ action: "school.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "school", targetId: schoolId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);
    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update school error:", error);
    return NextResponse.json(
      { error: "Failed to update school" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId } = await params;
    await deactivateSchool(schoolId);
    logAuditEvent({ action: "school.deactivate", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "school", targetId: schoolId, schoolId }).catch(console.error);
    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Deactivate school error:", error);
    return NextResponse.json(
      { error: "Failed to deactivate school" },
      { status: 500 }
    );
  }
}
