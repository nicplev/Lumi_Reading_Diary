import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { createSchool } from "@/lib/firestore/schools";
import { createSchoolSchema } from "@/lib/validations/school";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = createSchoolSchema.parse(body);

    const schoolId = await createSchool({
      ...parsed,
      contactEmail: parsed.contactEmail || undefined,
      createdBy: session.uid,
    });

    logAuditEvent({ action: "school.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "school", targetId: schoolId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);
    return NextResponse.json({ id: schoolId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create school error:", error);
    return NextResponse.json(
      { error: "Failed to create school" },
      { status: 500 }
    );
  }
}
