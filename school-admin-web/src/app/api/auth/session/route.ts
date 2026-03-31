import { NextRequest, NextResponse } from 'next/server';
import { adminAuth, adminDb } from '@/lib/firebase/admin';
import { createSessionCookie, SessionData } from '@/lib/auth/session';

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
    },
  };
}

export async function POST(request: NextRequest) {
  try {
    const { idToken } = await request.json();
    if (!idToken) {
      return NextResponse.json({ error: 'Missing ID token' }, { status: 400 });
    }

    // Verify the ID token
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const uid = decodedToken.uid;
    const email = decodedToken.email || '';
    const name = decodedToken.name || '';

    // Fast path: check custom claims for cached schoolId (O(1) lookup)
    if (decodedToken.schoolId) {
      const result = await findUserInSchool(decodedToken.schoolId as string, uid, email, name);
      if (result) {
        if (result.response) return result.response;
        await createSessionCookie(result.userData);
        return NextResponse.json(result.userData);
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

    // Cache schoolId as custom claim for faster future logins
    await adminAuth.setCustomUserClaims(uid, {
      ...(decodedToken.customClaims || {}),
      schoolId: userData.schoolId,
    });

    await createSessionCookie(userData);
    return NextResponse.json(userData);
  } catch (error) {
    console.error('Session creation error:', error);
    return NextResponse.json({ error: 'Authentication failed' }, { status: 401 });
  }
}
