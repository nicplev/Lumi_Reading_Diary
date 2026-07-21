import { NextResponse } from "next/server";
import { verifySession } from "@/lib/auth";
import { isSuperAdminViaFirestore } from "@/lib/auth-firestore";
import { hasMfa, resetMfa } from "@/lib/mfa/store";
import { logAuditEvent } from "@/lib/firestore/audit-log";

// Portal peer-reset: a logged-in (therefore MFA-satisfied) super-admin clears
// ANOTHER super-admin's TOTP enrollment, forcing fresh enrollment on their next
// login. Self-reset is refused (an active session must not be able to drop its
// own second factor — use the break-glass script for a self-lockout). Audited.
export async function POST(request: Request) {
  const session = await verifySession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { targetUid } = (await request.json().catch(() => ({}))) as {
    targetUid?: unknown;
  };
  if (!targetUid || typeof targetUid !== "string") {
    return NextResponse.json({ error: "targetUid required" }, { status: 400 });
  }
  if (targetUid === session.uid) {
    return NextResponse.json(
      { error: "Cannot reset your own MFA — use the break-glass script." },
      { status: 400 },
    );
  }
  if (!(await isSuperAdminViaFirestore(targetUid))) {
    return NextResponse.json({ error: "Target is not a super-admin" }, { status: 400 });
  }

  const wasEnrolled = await hasMfa(targetUid);
  await resetMfa(targetUid);
  await logAuditEvent({
    action: "adminMfa.reset",
    performedBy: session.uid,
    performedByEmail: session.email,
    targetType: "superAdmin",
    targetId: targetUid,
    metadata: { wasEnrolled },
  });

  return NextResponse.json({ status: "success" });
}
