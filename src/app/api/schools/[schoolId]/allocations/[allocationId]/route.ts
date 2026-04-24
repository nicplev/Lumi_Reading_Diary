import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import {
  updateAllocation,
  deactivateAllocation,
} from "@/lib/firestore/allocations";
import { updateAllocationSchema } from "@/lib/validations/allocation";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function PATCH(
  request: Request,
  {
    params,
  }: { params: Promise<{ schoolId: string; allocationId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, allocationId } = await params;
    const body = await request.json();
    const parsed = updateAllocationSchema.parse(body);

    await updateAllocation(schoolId, allocationId, parsed);

    logAuditEvent({ action: "allocation.update", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "allocation", targetId: allocationId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Update allocation error:", error);
    return NextResponse.json(
      { error: "Failed to update allocation" },
      { status: 500 }
    );
  }
}

export async function DELETE(
  _request: Request,
  {
    params,
  }: { params: Promise<{ schoolId: string; allocationId: string }> }
) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { schoolId, allocationId } = await params;
    await deactivateAllocation(schoolId, allocationId);

    logAuditEvent({ action: "allocation.deactivate", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "allocation", targetId: allocationId, schoolId }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Deactivate allocation error:", error);
    return NextResponse.json(
      { error: "Failed to deactivate allocation" },
      { status: 500 }
    );
  }
}
