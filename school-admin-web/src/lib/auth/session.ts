import { cookies } from 'next/headers';
import { SignJWT, jwtVerify } from 'jose';

export interface SessionData {
  uid: string;
  email: string;
  schoolId: string;
  role: 'teacher' | 'schoolAdmin';
  fullName: string;
}

const SESSION_COOKIE_NAME = 'lumi_session';
const SESSION_MAX_AGE = 60 * 60 * 24 * 5; // 5 days

function getSecret() {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error('SESSION_SECRET environment variable is required');
  return new TextEncoder().encode(secret);
}

export async function createSessionCookie(sessionData: SessionData) {
  const token = await new SignJWT({ ...sessionData })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${SESSION_MAX_AGE}s`)
    .sign(getSecret());

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: SESSION_MAX_AGE,
    path: '/',
  });
}

export async function getSession(): Promise<SessionData | null> {
  const cookieStore = await cookies();
  const cookie = cookieStore.get(SESSION_COOKIE_NAME);
  if (!cookie?.value) return null;

  try {
    const { payload } = await jwtVerify(cookie.value, getSecret());
    return {
      uid: payload.uid as string,
      email: payload.email as string,
      schoolId: payload.schoolId as string,
      role: payload.role as 'teacher' | 'schoolAdmin',
      fullName: payload.fullName as string,
    };
  } catch {
    // Backward compat: try parsing as plain JSON (for existing sessions during rollout)
    try {
      const data = JSON.parse(cookie.value);
      if (data.uid && data.schoolId && data.role) {
        return data as SessionData;
      }
    } catch {
      // Not valid JSON either
    }
    return null;
  }
}

export async function clearSession() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
