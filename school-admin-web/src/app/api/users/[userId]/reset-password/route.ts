import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { resetUserPassword } from '@/lib/firestore/users';

export async function POST(_request: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can reset passwords' }, { status: 403 });
  }

  const { userId } = await params;
  try {
    const link = await resetUserPassword(userId);
    return NextResponse.json({ link });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to generate reset link';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
