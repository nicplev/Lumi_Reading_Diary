import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  updateSchoolUser,
  deactivateSchoolUser,
} from "@/lib/firestore/school-users";
import { updateSchoolUserSchema } from "@/lib/validations/school-user";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ schoolId: string; userId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, userId } = await params;
    const body = await request.json();
    const parsed = updateSchoolUserSchema.parse(body);

    await updateSchoolUser(schoolId, userId, parsed);

    logAuditEvent({ action: "schoolUser.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "schoolUser", targetId: userId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update school user error:", error);
    return NextResponse.json(
      { error: "Failed to update user" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ schoolId: string; userId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, userId } = await params;
    await deactivateSchoolUser(schoolId, userId);

    logAuditEvent({ action: "schoolUser.deactivate", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "schoolUser", targetId: userId, schoolId }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Deactivate school user error:", error);
    return NextResponse.json(
      { error: "Failed to deactivate user" },
      { status: 500 }
    );
  }
}
