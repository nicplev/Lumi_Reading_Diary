import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getSchool } from '@/lib/firestore/school';
import {
  getReadingMetrics,
  getEngagementTrend,
  getLevelDistribution,
  getClassComparison,
  getAtRiskStudents,
  getTopReaders,
  getPopularBooks,
  resolvePeriod,
} from '@/lib/firestore/analytics';

const VALID_PERIODS = ['5days', 'month', 'term', 'year'] as const;
type Period = typeof VALID_PERIODS[number];

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { searchParams } = request.nextUrl;
  const rawPeriod = searchParams.get('period') ?? 'month';
  const termKey = searchParams.get('termKey') ?? null;

  if (!VALID_PERIODS.includes(rawPeriod as Period)) {
    return NextResponse.json({ error: 'Invalid period' }, { status: 400 });
  }
  const period = rawPeriod as Period;

  try {
    const school = await getSchool(session.schoolId);
    const termDates = school?.termDates ?? {};

    const { startDate, endDate, weekdaysOnly } = resolvePeriod(period, termKey, termDates);

    const [metrics, trend, levels, classes, atRisk, topReaders, books] = await Promise.all([
      getReadingMetrics(session.schoolId, startDate, endDate, weekdaysOnly),
      getEngagementTrend(session.schoolId, startDate, endDate, weekdaysOnly),
      getLevelDistribution(session.schoolId),
      getClassComparison(session.schoolId, startDate, endDate, weekdaysOnly),
      getAtRiskStudents(session.schoolId, 7),
      getTopReaders(session.schoolId, startDate, endDate, weekdaysOnly, 10),
      getPopularBooks(session.schoolId, startDate, endDate, weekdaysOnly, 15),
    ]);

    return NextResponse.json({ metrics, trend, levels, classes, atRisk, topReaders, books });
  } catch {
    return NextResponse.json({ error: 'Failed to fetch analytics' }, { status: 500 });
  }
}
