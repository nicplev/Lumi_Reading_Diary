import { cookies } from 'next/headers';

export interface SessionData {
  uid: string;
  email: string;
  schoolId: string;
  role: 'teacher' | 'schoolAdmin';
  fullName: string;
}

const SESSION_COOKIE_NAME = 'lumi_session';
const SESSION_MAX_AGE = 60 * 60 * 24 * 5; // 5 days

export async function createSessionCookie(sessionData: SessionData) {
  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, JSON.stringify(sessionData), {
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
    return JSON.parse(cookie.value) as SessionData;
  } catch {
    return null;
  }
}

export async function clearSession() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
