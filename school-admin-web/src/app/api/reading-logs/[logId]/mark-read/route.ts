import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { markCommentsRead } from '@/lib/firestore/reading-logs';

// Clears the staff unread badge on a log by stamping commentsViewedAt[uid].
export async function POST(
  _request: NextRequest,
  { params }: { params: Promise<{ logId: string }> }
) {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { logId } = await params;
  try {
    await markCommentsRead(session.schoolId, logId, session.uid);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ error: 'Failed to mark read' }, { status: 500 });
  }
}
