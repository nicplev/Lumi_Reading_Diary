import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getStaffCredential } from '@/lib/firestore/users';

export async function GET(_request: NextRequest, { params }: { params: Promise<{ userId: string }> }) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Only school admins can view credentials' }, { status: 403 });
  }

  const { userId } = await params;
  try {
    const cred = await getStaffCredential(session.schoolId, userId);
    if (!cred) {
      return NextResponse.json({ error: 'No active temporary password for this staff member' }, { status: 404 });
    }
    return NextResponse.json({
      tempPassword: cred.tempPassword,
      createdAt: cred.createdAt.toISOString(),
    });
  } catch {
    return NextResponse.json({ error: 'Failed to fetch credentials' }, { status: 500 });
  }
}
