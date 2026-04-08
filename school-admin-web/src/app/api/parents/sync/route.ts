import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { syncParentStudentLinks } from '@/lib/firestore/parents';

export async function POST() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const updatedCount = await syncParentStudentLinks(session.schoolId);
    return NextResponse.json({ updatedCount });
  } catch {
    return NextResponse.json({ error: 'Failed to sync parent links' }, { status: 500 });
  }
}
