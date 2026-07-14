import { cookies } from 'next/headers';
import { SignJWT, jwtVerify } from 'jose';
import { adminDb } from '@/lib/firebase/admin';

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
  /** Chosen staff Lumi character id; renders in the profile chip. */
  characterId?: string;
  /**
   * True only after the server has verified the second-factor requirement for
   * this session. Admin sessions without this bit are rejected, which also
   * invalidates admin cookies minted before mandatory MFA was introduced.
   */
  mfaVerified?: boolean;
  /** Server-verified exception for the isolated, synthetic, read-only demo. */
  mfaExemptReason?: 'isolatedDemoReadOnly';
  /** Present iff a developer impersonation session is active. */
  impersonation?: ImpersonationSessionBlock;
}

// MUST be '__session' — Firebase Hosting strips every cookie except this one
// before forwarding to the backend (CDN caching). Any other name silently
// breaks auth: the cookie is Set on the browser but never reaches Cloud Run
// on subsequent requests, so middleware always redirects to /login.
const SESSION_COOKIE_NAME = '__session';
const SESSION_MAX_AGE = 60 * 60 * 24 * 5; // 5 days
const MFA_ENROLLMENT_ISSUER = 'lumi-school-admin';
const MFA_ENROLLMENT_AUDIENCE = 'admin-totp-enrollment';
const MFA_ENROLLMENT_MAX_AGE = '10m';

// The shared sales-demo school. Its login accounts use a rolling daily password
// (scrambled just after Sydney midnight — see functions/src/demo_access.ts), so
// a demo-school session must not outlive the day. We cap it to end-of-day Sydney
// instead of the usual 5 days — the __session JWT is only locally verified, so a
// session opened on demo day would otherwise stay valid long after the password
// was scrambled.
const DEMO_ACCESS_SCHOOL_ID = 'lumi_demo_primary_school';
const DEMO_ACCESS_TIMEZONE = 'Australia/Sydney';

// Seconds from now until the next Sydney midnight (min 60s so a login right at
// midnight still gets a usable session). DST transitions can make this off by up
// to an hour — harmless for a session cap.
function secondsUntilSydneyEndOfDay(now: Date = new Date()): number {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: DEMO_ACCESS_TIMEZONE,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(now);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? '0');
  const hour = get('hour') % 24; // some ICU builds render midnight as 24
  const elapsed = hour * 3600 + get('minute') * 60 + get('second');
  return Math.max(86400 - elapsed, 60);
}

// Cookie/JWT lifetime for a school: the usual 5 days, capped to end-of-day
// Sydney for the shared demo school so a session can't outlive the day password.
function sessionMaxAgeForSchool(schoolId: string): number {
  return schoolId === DEMO_ACCESS_SCHOOL_ID
    ? Math.min(SESSION_MAX_AGE, secondsUntilSydneyEndOfDay())
    : SESSION_MAX_AGE;
}

function getSecret() {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error('SESSION_SECRET environment variable is required');
  return new TextEncoder().encode(secret);
}

export async function createSessionCookie(sessionData: SessionData) {
  // Cap the demo school here rather than at the call site so no caller can
  // forget it — the JWT `exp` and the cookie maxAge are set together, since
  // capping only the cookie would leave a replayed token verifiable for 5 days.
  const maxAgeSeconds = sessionMaxAgeForSchool(sessionData.schoolId);
  const token = await new SignJWT({ ...sessionData })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${maxAgeSeconds}s`)
    .sign(getSecret());

  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: maxAgeSeconds,
    path: '/',
  });
}

/**
 * A short-lived proof that this user supplied a valid primary credential and
 * was identified server-side as a school admin who still needs TOTP. It lets
 * the first, OTP-confirmed enrollment complete without weakening all future
 * admin logins, which must contain Firebase's `sign_in_second_factor=totp`
 * claim.
 */
export async function createAdminMfaEnrollmentToken(uid: string) {
  return new SignJWT({ uid, purpose: MFA_ENROLLMENT_AUDIENCE })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(MFA_ENROLLMENT_ISSUER)
    .setAudience(MFA_ENROLLMENT_AUDIENCE)
    .setIssuedAt()
    .setExpirationTime(MFA_ENROLLMENT_MAX_AGE)
    .sign(getSecret());
}

export async function verifyAdminMfaEnrollmentToken(
  token: string | undefined,
  uid: string,
): Promise<boolean> {
  if (!token) return false;

  try {
    const { payload } = await jwtVerify(token, getSecret(), {
      algorithms: ['HS256'],
      issuer: MFA_ENROLLMENT_ISSUER,
      audience: MFA_ENROLLMENT_AUDIENCE,
    });
    return payload.uid === uid && payload.purpose === MFA_ENROLLMENT_AUDIENCE;
  } catch {
    return false;
  }
}

export async function getSession(
  options: { requireMutable?: boolean } = {},
): Promise<SessionData | null> {
  const cookieStore = await cookies();
  const cookie = cookieStore.get(SESSION_COOKIE_NAME);
  if (!cookie?.value) return null;

  try {
    const { payload } = await jwtVerify(cookie.value, getSecret(), {
      algorithms: ['HS256'],
    });
    const role = payload.role;
    if (
      typeof payload.uid !== 'string' ||
      typeof payload.email !== 'string' ||
      typeof payload.schoolId !== 'string' ||
      (role !== 'teacher' && role !== 'schoolAdmin') ||
      typeof payload.fullName !== 'string'
    ) {
      return null;
    }

    // Mandatory MFA is enforced here as well as at cookie issuance. This
    // rejects every pre-rollout admin cookie and protects API handlers that
    // call getSession() even if middleware is bypassed.
    const hasAdminMfa =
      payload.mfaVerified === true ||
      payload.mfaExemptReason === 'isolatedDemoReadOnly';
    if (role === 'schoolAdmin' && !hasAdminMfa) {
      return null;
    }

    // Route handlers that mutate through the Admin SDK must opt into this
    // check. Admin SDK writes bypass Firestore Rules, and middleware is only a
    // first-line convenience guard, so both read-only session types must be
    // rejected again at the handler's authentication boundary.
    if (
      options.requireMutable === true &&
      (payload.mfaExemptReason === 'isolatedDemoReadOnly' || payload.impersonation)
    ) {
      return null;
    }

    // Bind NORMAL sessions to current server state. The __session JWT is
    // stateless and only locally verified, so deactivating, deleting or
    // demoting a user in Firestore does NOT otherwise invalidate an already
    // issued cookie until it expires (up to SESSION_MAX_AGE ≈ 5 days). Re-read
    // the staff doc and reject on a definitive negative:
    //   • doc missing / isActive:false / pendingDeletion:true → deactivated or
    //     deleted user is logged out (they cannot log in again either).
    //   • role changed → force a clean re-login so a demoted admin drops back
    //     to teacher instead of keeping schoolAdmin from the stale token.
    // Impersonation and demo sessions are skipped: their effective role/schoolId
    // is intentionally not the real user's doc, and both are short-lived and
    // separately gated. A transient Firestore error fails OPEN (the JWT is
    // already cryptographically verified) so a blip can't log out every user;
    // the bounded staleness window is exactly what this narrows, not a new hole.
    if (!payload.impersonation && payload.mfaExemptReason !== 'isolatedDemoReadOnly') {
      try {
        const snap = await adminDb
          .collection('schools').doc(payload.schoolId as string)
          .collection('users').doc(payload.uid as string)
          .get();
        const u = snap.data();
        if (!snap.exists || u?.isActive === false || u?.pendingDeletion === true) {
          return null;
        }
        if (u?.role !== role) {
          return null;
        }
      } catch (err) {
        console.error('getSession: server-state re-check failed, proceeding on verified JWT', err);
      }
    }

    return {
      uid: payload.uid as string,
      email: payload.email as string,
      schoolId: payload.schoolId as string,
      role,
      fullName: payload.fullName as string,
      characterId: payload.characterId as string | undefined,
      mfaVerified: payload.mfaVerified === true,
      mfaExemptReason:
        payload.mfaExemptReason === 'isolatedDemoReadOnly'
          ? 'isolatedDemoReadOnly'
          : undefined,
      impersonation: payload.impersonation as ImpersonationSessionBlock | undefined,
    };
  } catch {
    // Invalid or unsigned cookie — never trust it. (A plain-JSON fallback here
    // would let anyone forge an admin session by setting the cookie by hand.)
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
