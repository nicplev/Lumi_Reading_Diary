import { NextRequest, NextResponse } from 'next/server';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { adminAuth, adminDb } from '@/lib/firebase/admin';
import {
  createAdminMfaEnrollmentToken,
  createSessionCookie,
  type SessionData,
  verifyAdminMfaEnrollmentToken,
} from '@/lib/auth/session';

// Mandatory by default. Setting this to "false" is an emergency rollback only;
// production should enable TOTP in Firebase Identity Platform before deploy.
const ADMIN_TOTP_ENFORCED = process.env.ADMIN_TOTP_ENFORCED !== 'false';
const ADMIN_RECENT_LOGIN_SECONDS = 5 * 60;

async function findUserInSchool(schoolId: string, uid: string, email: string, decodedName: string): Promise<{ userData: SessionData; response?: never } | { userData?: never; response: NextResponse } | null> {
  const userDoc = await adminDb
    .collection('schools')
    .doc(schoolId)
    .collection('users')
    .doc(uid)
    .get();

  if (!userDoc.exists) return null;

  const data = userDoc.data()!;

  // Block deactivated users
  if (data.isActive === false) {
    return {
      response: NextResponse.json(
        { error: 'Your account has been deactivated. Contact your school administrator.' },
        { status: 403 }
      ),
    };
  }

  const role = data.role as string;

  // Only allow teacher and schoolAdmin roles
  if (role !== 'teacher' && role !== 'schoolAdmin') {
    return {
      response: NextResponse.json(
        { error: 'Access denied. Only school staff can access the admin portal.' },
        { status: 403 }
      ),
    };
  }

  return {
    userData: {
      uid,
      email: data.email || email || '',
      schoolId,
      role: role as 'teacher' | 'schoolAdmin',
      fullName: data.fullName || decodedName || '',
      characterId: data.characterId,
    },
  };
}

async function issuePortalSession(
  userData: SessionData,
  decodedToken: DecodedIdToken,
  enrollmentToken?: string,
): Promise<NextResponse> {
  // A demo exemption is accepted only when three independent server-side
  // facts agree: Admin-SDK custom claims, the claimed school id, and the
  // Firestore tenant's immutable operational marker. A client-editable email
  // or profile field is never sufficient.
  let isReadOnlyDemoAdmin = false;
  let demoGenerationId: string | undefined;
  if (
    userData.role === 'schoolAdmin' &&
    decodedToken.demoAccount === true &&
    decodedToken.demoAdminMfaExempt === true &&
    decodedToken.demoReadOnly === true &&
    decodedToken.demoSchoolId === userData.schoolId
  ) {
    const schoolRef = adminDb.collection('schools').doc(userData.schoolId);
    const [school, reseedStatus] = await Promise.all([
      schoolRef.get(),
      adminDb.collection('demoAccess').doc('reseedStatus').get(),
    ]);
    const leaseId = reseedStatus.data()?.leaseId;
    isReadOnlyDemoAdmin =
      school.exists &&
      school.data()?.isDemo === true &&
      reseedStatus.data()?.state === 'succeeded' &&
      reseedStatus.data()?.schoolId === userData.schoolId &&
      typeof leaseId === 'string' &&
      leaseId.length > 0 &&
      decodedToken.demoGenerationId === leaseId;
    if (isReadOnlyDemoAdmin) demoGenerationId = leaseId;
  }

  if (userData.role === 'schoolAdmin' && ADMIN_TOTP_ENFORCED && !isReadOnlyDemoAdmin) {
    const nowSeconds = Math.floor(Date.now() / 1000);
    if (decodedToken.auth_time < nowSeconds - ADMIN_RECENT_LOGIN_SECONDS) {
      return NextResponse.json(
        {
          code: 'admin-recent-login-required',
          error: 'Please sign in again to verify administrator access.',
        },
        { status: 401 },
      );
    }

    const authUser = await adminAuth.getUser(userData.uid);
    const hasTotp = (authUser.multiFactor?.enrolledFactors ?? []).some(
      (factor) => factor.factorId === 'totp',
    );

    if (!hasTotp) {
      return NextResponse.json(
        {
          code: 'admin-totp-enrollment-required',
          error: 'Authenticator app setup is required for administrator accounts.',
          enrollmentToken: await createAdminMfaEnrollmentToken(userData.uid),
        },
        { status: 403 },
      );
    }

    const signedInWithTotp =
      decodedToken.firebase?.sign_in_second_factor === 'totp';
    // The first enrollment validates a live OTP but its refreshed ID token is
    // not guaranteed to carry a sign-in-second-factor claim. Accept it only
    // alongside the short-lived, uid-bound proof issued immediately before
    // enrollment. Every later login must carry Firebase's TOTP claim.
    const completedFirstEnrollment =
      !signedInWithTotp &&
      (await verifyAdminMfaEnrollmentToken(enrollmentToken, userData.uid));

    if (!signedInWithTotp && !completedFirstEnrollment) {
      return NextResponse.json(
        {
          code: 'admin-totp-required',
          error: 'Enter the code from your authenticator app to continue.',
        },
        { status: 403 },
      );
    }
  }

  const verifiedSession: SessionData = {
    ...userData,
    // When enforcement is disabled this remains true so the central session
    // validator can serve as a clean emergency rollback without code changes.
    mfaVerified:
      userData.role === 'schoolAdmin'
        ? !isReadOnlyDemoAdmin
        : Boolean(decodedToken.firebase?.sign_in_second_factor),
    mfaExemptReason: isReadOnlyDemoAdmin
      ? 'isolatedDemoReadOnly'
      : undefined,
    demoGenerationId,
    demoAllocationMutations: isReadOnlyDemoAdmin ? true : undefined,
    // Pins the session to this sign-in. getSession() compares it against the
    // account's tokensValidAfterTime, so revoking tokens (or a password reset)
    // ends the portal session instead of leaving the cookie valid for days.
    authTime:
      typeof decodedToken.auth_time === 'number' ? decodedToken.auth_time : undefined,
  };
  await createSessionCookie(verifiedSession);
  return NextResponse.json(verifiedSession);
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const idToken = body?.idToken;
    const enrollmentToken = body?.enrollmentToken;
    if (typeof idToken !== 'string' || idToken.length === 0 || idToken.length > 10000) {
      return NextResponse.json({ error: 'Missing ID token' }, { status: 400 });
    }
    if (enrollmentToken !== undefined && typeof enrollmentToken !== 'string') {
      return NextResponse.json({ error: 'Invalid enrollment token' }, { status: 400 });
    }

    // Verify signature, issuer, audience, expiry, and revocation.
    const decodedToken = await adminAuth.verifyIdToken(idToken, true);
    const uid = decodedToken.uid;
    const email = decodedToken.email || '';
    const name = decodedToken.name || '';

    // Fast path: check custom claims for cached schoolId (O(1) lookup)
    if (decodedToken.schoolId) {
      const result = await findUserInSchool(decodedToken.schoolId as string, uid, email, name);
      if (result) {
        if (result.response) return result.response;
        return issuePortalSession(result.userData, decodedToken, enrollmentToken);
      }
      // Claim is stale (user moved/deleted from that school) — fall through to full scan
    }

    // Slow path: scan all schools (first login or stale claim)
    const schoolsSnapshot = await adminDb.collection('schools').get();
    let userData: SessionData | null = null;

    for (const schoolDoc of schoolsSnapshot.docs) {
      const result = await findUserInSchool(schoolDoc.id, uid, email, name);
      if (result) {
        if (result.response) return result.response;
        userData = result.userData;
        break;
      }
    }

    if (!userData) {
      return NextResponse.json(
        { error: 'User not found in any school. Contact your administrator.' },
        { status: 404 }
      );
    }

    // Cache schoolId as custom claim for faster future logins.
    // NOTE: existing claims must come from adminAuth.getUser() — a decoded
    // ID token spreads custom claims onto its TOP level (there is no
    // `decodedToken.customClaims` property), so the old spread here was
    // always `{}` and this call silently WIPED every other custom claim
    // the user had whenever the slow path ran.
    const userRecord = await adminAuth.getUser(uid);
    await adminAuth.setCustomUserClaims(uid, {
      ...(userRecord.customClaims ?? {}),
      schoolId: userData.schoolId,
    });

    return issuePortalSession(userData, decodedToken, enrollmentToken);
  } catch (error) {
    console.error('Session creation error:', error);
    return NextResponse.json({ error: 'Authentication failed' }, { status: 401 });
  }
}
