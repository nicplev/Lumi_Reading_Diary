import "server-only";
import { cookies } from "next/headers";
import { createHmac, timingSafeEqual } from "node:crypto";
import { getAdminAuth } from "./firebase-admin";
import { isSuperAdminViaFirestore } from "./auth-firestore";

const SESSION_COOKIE_NAME = "__session";
const MAX_AGE = parseInt(process.env.SESSION_COOKIE_MAX_AGE || "432000", 10);

export interface AdminSession {
  uid: string;
  email?: string;
  name?: string;
  authTime: number;
  issuedAt: number;
  expiresAt: number;
}

function sessionSecret(): string {
  const secret = process.env.ADMIN_SESSION_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error("ADMIN_SESSION_SECRET must contain at least 32 characters");
  }
  return secret;
}

function signPayload(encodedPayload: string): Buffer {
  return createHmac("sha256", sessionSecret()).update(encodedPayload).digest();
}

function encodeSession(session: AdminSession): string {
  const payload = Buffer.from(JSON.stringify({ v: 1, ...session }))
    .toString("base64url");
  return `${payload}.${signPayload(payload).toString("base64url")}`;
}

function decodeSession(token: string): AdminSession | null {
  const parts = token.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  try {
    const supplied = Buffer.from(parts[1], "base64url");
    const expected = signPayload(parts[0]);
    if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
      return null;
    }
    const payload = JSON.parse(
      Buffer.from(parts[0], "base64url").toString("utf8"),
    ) as Partial<AdminSession> & { v?: unknown };
    const now = Math.floor(Date.now() / 1000);
    if (
      payload.v !== 1 ||
      typeof payload.uid !== "string" ||
      payload.uid.length === 0 ||
      (payload.email !== undefined && typeof payload.email !== "string") ||
      (payload.name !== undefined && typeof payload.name !== "string") ||
      !Number.isInteger(payload.authTime) ||
      !Number.isInteger(payload.issuedAt) ||
      !Number.isInteger(payload.expiresAt) ||
      (payload.authTime as number) > now + 60 ||
      (payload.issuedAt as number) > now + 60 ||
      (payload.expiresAt as number) <= now ||
      (payload.expiresAt as number) > now + MAX_AGE + 60
    ) {
      return null;
    }
    return payload as AdminSession;
  } catch {
    return null;
  }
}

export async function createSession(idToken: string) {
  const decoded = await getAdminAuth().verifyIdToken(idToken, true);
  const issuedAt = Math.floor(Date.now() / 1000);
  const sessionCookie = encodeSession({
    uid: decoded.uid,
    email: decoded.email,
    name: decoded.name,
    authTime: decoded.auth_time,
    issuedAt,
    expiresAt: issuedAt + MAX_AGE,
  });

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, sessionCookie, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: MAX_AGE,
  });
}

export async function verifySession(): Promise<AdminSession | null> {
  const cookieStore = await cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!sessionCookie) return null;

  try {
    const decoded = decodeSession(sessionCookie);
    if (!decoded) return null;

    // Bind the signed cookie to current Auth state. Disabling/deleting the
    // account or revoking refresh tokens invalidates the portal session even
    // before its five-day expiry.
    const user = await getAdminAuth().getUser(decoded.uid);
    if (user.disabled) return null;
    const validAfter = user.tokensValidAfterTime ?
      Math.floor(new Date(user.tokensValidAfterTime).getTime() / 1000) :
      0;
    if (validAfter > decoded.authTime) return null;
    // Re-check super-admin membership on EVERY request, not just at login.
    // verifySessionCookie(…, checkRevoked=true) only catches token revocation /
    // account disable — NOT removal from the /superAdmins allowlist. Without
    // this, a de-provisioned super-admin keeps full portal access until the
    // ~5-day session cookie expires. This reuses the exact gate applied at
    // login (isSuperAdminViaFirestore, incl. the SUPER_ADMIN_UIDS bootstrap),
    // so nothing changes for current super-admins.
    if (!(await isSuperAdminViaFirestore(decoded.uid))) return null;
    return decoded;
  } catch {
    return null;
  }
}

export async function destroySession() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
