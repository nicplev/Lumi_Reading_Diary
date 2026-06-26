import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getReadingGroupStats } from '@/lib/firestore/reading-groups';

/** This-week performance per reading group for a class (?classId, optional ?since days). */
export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId');
  if (!classId) return NextResponse.json({ error: 'classId is required' }, { status: 400 });

  const sinceParam = parseInt(searchParams.get('since') ?? '', 10);
  const sinceDays = Number.isFinite(sinceParam) ? Math.max(1, Math.min(90, sinceParam)) : 7;

  try {
    const stats = await getReadingGroupStats(session.schoolId, classId, sinceDays);
    return NextResponse.json(stats);
  } catch {
    return NextResponse.json({ error: 'Failed to load reading group stats' }, { status: 500 });
  }
}
