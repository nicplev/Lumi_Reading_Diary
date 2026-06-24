import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getClassReport } from '@/lib/firestore/reports';

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = new URL(request.url);
  const classId = searchParams.get('classId');
  if (!classId) return NextResponse.json({ error: 'classId is required' }, { status: 400 });

  const toParam = searchParams.get('to');
  const fromParam = searchParams.get('from');

  const to = toParam ? new Date(toParam) : new Date();
  const from = fromParam
    ? new Date(fromParam)
    : (() => {
        const d = new Date(to);
        d.setDate(d.getDate() - 30);
        return d;
      })();

  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
    return NextResponse.json({ error: 'Invalid date range' }, { status: 400 });
  }

  // Inclusive day boundaries.
  from.setHours(0, 0, 0, 0);
  to.setHours(23, 59, 59, 999);

  try {
    const report = await getClassReport(session.schoolId, classId, from, to);
    return NextResponse.json(report);
  } catch {
    return NextResponse.json({ error: 'Failed to build report' }, { status: 500 });
  }
}
