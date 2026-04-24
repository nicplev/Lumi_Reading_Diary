import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createAllocation } from "@/lib/firestore/allocations";
import { createAllocationSchema } from "@/lib/validations/allocation";
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
    const parsed = createAllocationSchema.parse(body);

    const allocationId = await createAllocation(schoolId, {
      ...parsed,
      createdBy: session.uid,
    });
    logAuditEvent({ action: "allocation.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "allocation", targetId: allocationId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ id: allocationId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create allocation error:", error);
    return NextResponse.json(
      { error: "Failed to create allocation" },
      { status: 500 }
    );
  }
}
