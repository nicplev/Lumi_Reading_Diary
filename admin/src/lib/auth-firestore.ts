import "server-only";
import { getAdminDb } from "./firebase-admin";

// Mirrors functions/src/super_admin.ts#isSuperAdmin — duplicated here to avoid a
// Cloud Function round-trip at auth time. Both must stay in sync: primary check
// is the /superAdmins/{uid} doc, SUPER_ADMIN_UIDS env is a bootstrap-only fallback.
export async function isSuperAdminViaFirestore(
  uid: string | undefined | null
): Promise<boolean> {
  if (!uid) return false;

  const doc = await getAdminDb().collection("superAdmins").doc(uid).get();
  if (doc.exists) return true;

  const envList = (process.env.SUPER_ADMIN_UIDS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return envList.includes(uid);
}
