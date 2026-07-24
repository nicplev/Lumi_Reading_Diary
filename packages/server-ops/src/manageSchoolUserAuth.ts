import type { Auth } from "firebase-admin/auth";
import type { Firestore } from "firebase-admin/firestore";
import { z } from "zod";
import { logAuditEvent, ServerOpsValidationError, type Actor } from "./audit";
import { assertSuperAdmin } from "./authority";

const paramsSchema = z.object({
  schoolId: z.string().min(1, "schoolId is required"),
  userId: z.string().min(1, "userId is required"),
  action: z.enum(["disable", "enable", "resetPassword"]),
});

export interface ManageSchoolUserAuthParams {
  schoolId: string;
  userId: string;
  action: "disable" | "enable" | "resetPassword";
}

export interface ManageSchoolUserAuthResult {
  success: true;
  resetLink?: string;
}

// Three Firebase Auth mutations gated as one operation: disable / enable the
// user, or generate a password-reset link. resetLink only appears on the
// resetPassword response; the admin UI surfaces it as a copyable URL.
export async function manageSchoolUserAuth(
  auth: Auth,
  db: Firestore,
  actor: Actor,
  params: ManageSchoolUserAuthParams
): Promise<ManageSchoolUserAuthResult> {
  await assertSuperAdmin(db, actor.uid);
  const parsed = paramsSchema.safeParse(params);
  if (!parsed.success) {
    throw new ServerOpsValidationError(
      parsed.error.issues.map((e) => e.message).join(", ")
    );
  }
  const { schoolId, userId, action } = parsed.data;

  let resetLink: string | undefined;

  if (action === "disable") {
    await auth.updateUser(userId, { disabled: true });
  } else if (action === "enable") {
    await auth.updateUser(userId, { disabled: false });
  } else {
    const user = await auth.getUser(userId);
    if (!user.email) {
      throw new ServerOpsValidationError("User has no email address");
    }
    resetLink = await auth.generatePasswordResetLink(user.email);
  }

  await logAuditEvent(db, {
    action: "schoolUser.auth",
    performedBy: actor.uid,
    performedByEmail: actor.email,
    targetType: "schoolUser",
    targetId: userId,
    schoolId,
    after: { action },
  }).catch((e) => {
    console.error("[server-ops] audit log failed for schoolUser.auth", e);
  });

  return resetLink ? { success: true, resetLink } : { success: true };
}
