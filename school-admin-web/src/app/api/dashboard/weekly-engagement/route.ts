import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getWeeklyEngagement } from '@/lib/firestore/dashboard';

/**
 * Per-weekday engagement for one Monday-anchored school-local week, selected
 * by `offset` (0 = this week, -1 = last week…). Powers the dashboard weekly
 * chart's timeframe selector.
 */
export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const raw = new URL(request.url).searchParams.get('offset');
  const parsed = raw === null ? 0 : Number(raw);
  if (!Number.isInteger(parsed)) {
    return NextResponse.json({ error: 'Invalid offset' }, { status: 400 });
  }
  // Bound the lookback so a bad param can't drive an unbounded historic scan.
  const offset = Math.min(0, Math.max(-12, parsed));

  try {
    const data = await getWeeklyEngagement(session.schoolId, offset);
    return NextResponse.json(data);
  } catch {
    return NextResponse.json({ error: 'Failed to load weekly engagement' }, { status: 500 });
  }
}
