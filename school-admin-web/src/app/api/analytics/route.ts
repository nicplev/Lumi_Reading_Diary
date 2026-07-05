import { NextRequest, NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getSchool } from '@/lib/firestore/school';
import {
  getReadingMetrics,
  getEngagementTrend,
  getClassEngagementTrend,
  getLevelDistribution,
  getClassComparison,
  getAtRiskStudents,
  getTopReaders,
  getPopularBooks,
  fetchReadingLogsInRange,
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

    // Fetch the period's reading logs ONCE and share them across every
    // log-based aggregator — was 5 identical full-period scans per load
    // (5× a full-year scan on "year"), which timed out on big schools and
    // surfaced as a misleading "No data". levels + atRisk read `students`, not
    // logs, so they keep their own reads.
    const logDocs = await fetchReadingLogsInRange(session.schoolId, startDate, endDate);

    const [metrics, trend, classTrend, levels, classes, atRisk, topReaders, books] = await Promise.all([
      getReadingMetrics(session.schoolId, startDate, endDate, weekdaysOnly, logDocs),
      getEngagementTrend(session.schoolId, startDate, endDate, weekdaysOnly, logDocs),
      getClassEngagementTrend(session.schoolId, startDate, endDate, weekdaysOnly, logDocs),
      getLevelDistribution(session.schoolId),
      getClassComparison(session.schoolId, startDate, endDate, weekdaysOnly, logDocs),
      getAtRiskStudents(session.schoolId, 7),
      getTopReaders(session.schoolId, startDate, endDate, weekdaysOnly, 10, logDocs),
      getPopularBooks(session.schoolId, startDate, endDate, weekdaysOnly, 15, logDocs),
    ]);

    return NextResponse.json({ metrics, trend, classTrend, levels, classes, atRisk, topReaders, books });
  } catch {
    return NextResponse.json({ error: 'Failed to fetch analytics' }, { status: 500 });
  }
}
