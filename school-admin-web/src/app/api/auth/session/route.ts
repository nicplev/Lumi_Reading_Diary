import { NextRequest, NextResponse } from 'next/server';
import { adminAuth, adminDb } from '@/lib/firebase/admin';
import { createSessionCookie, SessionData } from '@/lib/auth/session';

export async function POST(request: NextRequest) {
  try {
    const { idToken } = await request.json();
    if (!idToken) {
      return NextResponse.json({ error: 'Missing ID token' }, { status: 400 });
    }

    // Verify the ID token
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Find user in Firestore — search across all schools
    const schoolsSnapshot = await adminDb.collection('schools').get();
    let userData: SessionData | null = null;

    for (const schoolDoc of schoolsSnapshot.docs) {
      const userDoc = await adminDb
        .collection('schools')
        .doc(schoolDoc.id)
        .collection('users')
        .doc(uid)
        .get();

      if (userDoc.exists) {
        const data = userDoc.data()!;
        const role = data.role as string;

        // Only allow teacher and schoolAdmin roles
        if (role !== 'teacher' && role !== 'schoolAdmin') {
          return NextResponse.json(
            { error: 'Access denied. Only school staff can access the admin portal.' },
            { status: 403 }
          );
        }

        userData = {
          uid,
          email: data.email || decodedToken.email || '',
          schoolId: schoolDoc.id,
          role: role as 'teacher' | 'schoolAdmin',
          fullName: data.fullName || '',
        };
        break;
      }
    }

    if (!userData) {
      return NextResponse.json(
        { error: 'User not found in any school. Contact your administrator.' },
        { status: 404 }
      );
    }

    await createSessionCookie(userData);
    return NextResponse.json(userData);
  } catch (error) {
    console.error('Session creation error:', error);
    return NextResponse.json({ error: 'Authentication failed' }, { status: 401 });
  }
}
