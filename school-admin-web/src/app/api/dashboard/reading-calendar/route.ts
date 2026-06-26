import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getTeacherReadingCalendar } from '@/lib/firestore/dashboard';

/**
 * Daily reading-log counts for the teacher's classes over the last few weeks,
 * powering the dashboard heatmap. Fetched lazily by the calendar widget so the
 * wider 6-week scan only runs when a teacher actually shows that widget.
 */
export async function GET() {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const days = await getTeacherReadingCalendar(session.schoolId, session.uid);
    return NextResponse.json(days);
  } catch {
    return NextResponse.json({ error: 'Failed to load reading calendar' }, { status: 500 });
  }
}
