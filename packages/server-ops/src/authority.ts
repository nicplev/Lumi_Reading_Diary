import type { Firestore } from "firebase-admin/firestore";

// Thrown when the actor behind a privileged server-op is not a super-admin.
export class ServerOpsAuthorizationError extends Error {
  constructor(message = "Actor is not authorized for this operation") {
    super(message);
    this.name = "ServerOpsAuthorizationError";
  }
}

/**
 * Defence in depth for the destructive super-admin operations (offboard a
 * school, delete parent accounts, grant dev-access, disable staff auth). These
 * ops are only ever reached through a super-admin portal route that already
 * verified the session, but re-verifying the actor here means a route that ever
 * forgets to gate fails CLOSED instead of executing (finding F-04).
 *
 * Mirrors admin/src/lib/auth-firestore.ts#isSuperAdminViaFirestore and
 * functions/src/super_admin.ts#isSuperAdmin — primary check is the
 * /superAdmins/{uid} doc; SUPER_ADMIN_UIDS is a bootstrap-only env fallback.
 * All three must stay in sync.
 */
export async function assertSuperAdmin(
  db: Firestore,
  uid: string | undefined | null,
): Promise<void> {
  if (uid) {
    const doc = await db.collection("superAdmins").doc(uid).get();
    if (doc.exists) return;
    const envList = (process.env.SUPER_ADMIN_UIDS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter((s) => s.length > 0);
    if (envList.includes(uid)) return;
  }
  throw new ServerOpsAuthorizationError();
}
