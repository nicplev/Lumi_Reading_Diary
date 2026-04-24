import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth } from "@/lib/firebase-admin";
import { createSchoolUser } from "@/lib/firestore/school-users";
import { createSchoolUserSchema } from "@/lib/validations/school-user";
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
    const parsed = createSchoolUserSchema.parse(body);

    // Find or create Firebase Auth user
    let authUid: string;
    try {
      const existing = await getAdminAuth().getUserByEmail(parsed.email);
      authUid = existing.uid;
    } catch {
      const newUser = await getAdminAuth().createUser({
        email: parsed.email,
        displayName: parsed.fullName,
      });
      authUid = newUser.uid;
    }

    const userId = await createSchoolUser(schoolId, {
      authUid,
      email: parsed.email,
      fullName: parsed.fullName,
      role: parsed.role,
      classIds: parsed.classIds,
    });

    logAuditEvent({ action: "schoolUser.create", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "schoolUser", targetId: userId, schoolId, after: parsed as Record<string, unknown> }).catch(console.error);

    return NextResponse.json({ id: userId }, { status: 201 });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("Create school user error:", error);
    return NextResponse.json(
      { error: "Failed to create user" },
      { status: 500 }
    );
  }
}
