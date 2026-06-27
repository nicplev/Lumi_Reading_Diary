import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getLibraryAssignmentSnapshot } from '@/lib/firestore/library-assignments';

// Read-only "who has this book" snapshot for the school library, scoped to the
// session's school. Mirrors the app's staff-only assignment visibility.
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const snapshot = await getLibraryAssignmentSnapshot(session.schoolId, session.uid, session.role);
    return NextResponse.json(snapshot);
  } catch {
    return NextResponse.json({ error: 'Failed to load library assignments' }, { status: 500 });
  }
}
