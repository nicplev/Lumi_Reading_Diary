import { NextResponse } from 'next/server';
import { assertNotImpersonating } from '@/lib/auth/assert-not-impersonating';
import { getSession } from '@/lib/auth/session';
import { syncParentStudentLinks } from '@/lib/firestore/parents';

export async function POST() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json(
      { error: 'Only school admins can sync parent connections' },
      { status: 403 },
    );
  }
  const impersonationBlock = assertNotImpersonating(session);
  if (impersonationBlock) return impersonationBlock;

  try {
    const updatedCount = await syncParentStudentLinks(session.schoolId);
    return NextResponse.json({ updatedCount });
  } catch {
    return NextResponse.json({ error: 'Failed to sync parent links' }, { status: 500 });
  }
}
