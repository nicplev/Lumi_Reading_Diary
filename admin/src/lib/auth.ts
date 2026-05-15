import "server-only";
import { cookies } from "next/headers";
import { getAdminAuth } from "./firebase-admin";

const SESSION_COOKIE_NAME = "__session";
const MAX_AGE = parseInt(process.env.SESSION_COOKIE_MAX_AGE || "432000", 10);

export async function createSession(idToken: string) {
  const expiresIn = MAX_AGE * 1000; // milliseconds
  const sessionCookie = await getAdminAuth().createSessionCookie(idToken, {
    expiresIn,
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

export async function verifySession() {
  const cookieStore = await cookies();
  const sessionCookie = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!sessionCookie) return null;

  try {
    const decoded = await getAdminAuth().verifySessionCookie(sessionCookie, true);
    return decoded;
  } catch {
    return null;
  }
}

export async function destroySession() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
