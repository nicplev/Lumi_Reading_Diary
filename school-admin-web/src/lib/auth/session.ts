import { cookies } from 'next/headers';
import { SignJWT, jwtVerify } from 'jose';

export interface ImpersonationSessionBlock {
  sessionId: string;
  /** The Firestore user ID whose experience is being rendered. */
  targetUserId: string;
  /** Denormalized for banner rendering. */
  schoolName: string;
  /** Why the dev started this session (≥20 chars, stored verbatim). */
  reason: string;
  /** Unix ms. */
  startedAt: number;
  /** Unix ms; middleware enforces. */
  expiresAt: number;
  /** The real session's schoolId/role before impersonation, restored on exit. */
  realSchoolId: string;
  realRole: 'teacher' | 'schoolAdmin';
}

export interface SessionData {
  uid: string;
  email: string;
  /**
   * EFFECTIVE schoolId — equals the real schoolId in normal sessions, and the
   * IMPERSONATED school's id while `impersonation` is set. Every existing API
   * route that queries by `session.schoolId` therefore naturally reads from
   * the target school during impersonation without code changes.
   */
  schoolId: string;
  /** EFFECTIVE role — see note on schoolId above. */
  role: 'teacher' | 'schoolAdmin';
  fullName: string;
  /** Present iff a developer impersonation session is active. */
  impersonation?: ImpersonationSessionBlock;
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
      impersonation: payload.impersonation as ImpersonationSessionBlock | undefined,
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

export function isImpersonating(session: SessionData | null): boolean {
  return !!session?.impersonation;
}

export async function clearSession() {
  const cookieStore = await cookies();
  cookieStore.delete(SESSION_COOKIE_NAME);
}
