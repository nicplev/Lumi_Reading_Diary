import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { resetUserPassword } from '@/lib/firestore/users';

export async function POST() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Not authenticated' }, { status: 401 });
  }

  try {
    const link = await resetUserPassword(session.uid);
    return NextResponse.json({ link });
  } catch (error) {
    console.error('Password reset error:', error);
    return NextResponse.json(
      { error: 'Failed to generate password reset link' },
      { status: 500 }
    );
  }
}
