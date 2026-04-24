import { NextResponse } from "next/server";
import { z } from "zod";
import { verifySession } from "@/lib/auth";
import { createLinkCode } from "@/lib/firestore/link-codes";
import { logAuditEvent } from "@/lib/firestore/audit-log";

const createLinkCodeSchema = z.object({
  studentId: z.string().min(1, "Student ID is required"),
  schoolId: z.string().min(1, "School ID is required"),
  expiresInDays: z.number().int().min(1).optional(),
});

export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const body = await request.json();
    const parsed = createLinkCodeSchema.parse(body);

    const result = await createLinkCode({
      studentId: parsed.studentId,
      schoolId: parsed.schoolId,
      createdBy: session.uid,
      expiresInDays: parsed.expiresInDays,
    });

    logAuditEvent({ action: "linkCode.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "linkCode", targetId: result.id, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json(result, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create link code error:", error);
    return NextResponse.json(
      { error: "Failed to create link code" },
      { status: 500 }
    );
  }
}
