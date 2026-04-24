import * as admin from "firebase-admin";

/**
 * Super-admin check: returns true if the given Firebase UID holds super-admin
 * power (revoke impersonation sessions, export audit logs).
 *
 * Primary source: `/superAdmins/{uid}` Firestore collection. A super-admin
 * seeds this by hand via the Firebase console — presence is enough; no fields
 * are required.
 *
 * Bootstrap fallback: the `SUPER_ADMIN_UIDS` env var, comma-separated. Lets
 * the first super-admin seed the collection without a chicken-and-egg. Once
 * the collection has any members, the env var becomes dead code and should be
 * removed from the function config.
 *
 * @param {string | undefined | null} uid Firebase Auth UID to check.
 * @return {Promise<boolean>} true iff the UID is a super-admin.
 */
export async function isSuperAdmin(uid: string | undefined | null): Promise<boolean> {
  if (!uid) return false;

  const db = admin.firestore();
  const doc = await db.collection("superAdmins").doc(uid).get();
  if (doc.exists) return true;

  const envList = (process.env.SUPER_ADMIN_UIDS ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  return envList.includes(uid);
}
