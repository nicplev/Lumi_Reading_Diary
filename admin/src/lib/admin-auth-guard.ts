import "server-only";
import { getAdminAuth } from "@/lib/firebase-admin";
import { isSuperAdminViaFirestore } from "@/lib/auth-firestore";

// Shared gate for the login + MFA-enroll routes: a valid Firebase ID token
// belonging to a current super-admin, with a fresh sign-in (auth_time within
// 5 minutes). Reused so the two-step MFA flow applies exactly the same checks.

const AUTH_TIME_MAX_AGE_SEC = 5 * 60;

export type FreshAdminResult =
  | { ok: true; uid: string; email?: string }
  | { ok: false; status: number; error: string };

export async function verifyFreshSuperAdmin(
  idToken: unknown,
): Promise<FreshAdminResult> {
  if (!idToken || typeof idToken !== "string") {
    return { ok: false, status: 400, error: "Missing ID token" };
  }
  let decoded;
  try {
    decoded = await getAdminAuth().verifyIdToken(idToken);
  } catch {
    return { ok: false, status: 401, error: "Authentication failed" };
  }
  if (!(await isSuperAdminViaFirestore(decoded.uid))) {
    return { ok: false, status: 403, error: "Unauthorized" };
  }
  const cutoff = Math.floor(Date.now() / 1000) - AUTH_TIME_MAX_AGE_SEC;
  if (decoded.auth_time < cutoff) {
    return { ok: false, status: 401, error: "Session too old. Please sign in again." };
  }
  return { ok: true, uid: decoded.uid, email: decoded.email };
}
