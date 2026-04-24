import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { getAdminAuth } from "@/lib/firebase-admin";
import { userAuthActionSchema } from "@/lib/validations/school-user";
import { logAuditEvent } from "@/lib/firestore/audit-log";

export async function POST(
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
    const parsed = userAuthActionSchema.parse(body);

    const auth = getAdminAuth();

    switch (parsed.action) {
      case "disable":
        await auth.updateUser(userId, { disabled: true });
        break;
      case "enable":
        await auth.updateUser(userId, { disabled: false });
        break;
      case "resetPassword": {
        const user = await auth.getUser(userId);
        if (!user.email) {
          return NextResponse.json(
            { error: "User has no email address" },
            { status: 400 }
          );
        }
        const link = await auth.generatePasswordResetLink(user.email);
        logAuditEvent({ action: "schoolUser.auth", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "schoolUser", targetId: userId, schoolId, after: { action: parsed.action } }).catch(console.error);
        return NextResponse.json({ success: true, resetLink: link });
      }
    }

    logAuditEvent({ action: "schoolUser.auth", performedBy: session.uid, performedByEmail: session.email ?? undefined, targetType: "schoolUser", targetId: userId, schoolId, after: { action: parsed.action } }).catch(console.error);

    return NextResponse.json({ success: true });
  } catch (error: unknown) {
    if (error instanceof Error && error.name === "ZodError") {
      return NextResponse.json(
        { error: "Validation failed", details: (error as unknown as { errors: unknown }).errors },
        { status: 400 }
      );
    }
    console.error("User auth action error:", error);
    return NextResponse.json(
      { error: "Failed to perform auth action" },
      { status: 500 }
    );
  }
}
