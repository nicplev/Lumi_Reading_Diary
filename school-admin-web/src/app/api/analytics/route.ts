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
} from '@/lib/firestore/analytics';
import { resolvePeriod } from '@/lib/analytics-period';
import { DEFAULT_TIMEZONE } from '@/lib/time-core';

const VALID_PERIODS = ['5days', 'month', 'term', 'year'] as const;
type Period = typeof VALID_PERIODS[number];

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  // Admin-only (matches the sidebar's adminOnly flag): returns whole-school
  // data and a year-period load scans the school's entire log history.
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  }

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
    // Every date boundary below is computed in the school's timezone — the
    // server runs in a non-AU region, so its clock must never define a "day".
    const tz =
      typeof school?.timezone === 'string' && school.timezone.length > 0
        ? school.timezone
        : DEFAULT_TIMEZONE;

    const { startDate, endDate, weekdaysOnly } = resolvePeriod(period, termKey, termDates, tz);

    // Fetch the period's reading logs ONCE and share them across every
    // log-based aggregator — was 5 identical full-period scans per load
    // (5× a full-year scan on "year"), which timed out on big schools and
    // surfaced as a misleading "No data". levels + atRisk read `students`, not
    // logs, so they keep their own reads.
    const logDocs = await fetchReadingLogsInRange(session.schoolId, startDate, endDate);

    const [metrics, trend, classTrend, levels, classes, atRisk, topReaders, books] = await Promise.all([
      getReadingMetrics(session.schoolId, startDate, endDate, weekdaysOnly, tz, logDocs),
      getEngagementTrend(session.schoolId, startDate, endDate, weekdaysOnly, tz, logDocs),
      getClassEngagementTrend(session.schoolId, startDate, endDate, weekdaysOnly, tz, logDocs),
      getLevelDistribution(session.schoolId),
      getClassComparison(session.schoolId, startDate, endDate, weekdaysOnly, tz, logDocs),
      getAtRiskStudents(session.schoolId, 7, tz),
      getTopReaders(session.schoolId, startDate, endDate, weekdaysOnly, tz, 10, logDocs),
      getPopularBooks(session.schoolId, startDate, endDate, weekdaysOnly, tz, 15, logDocs),
    ]);

    return NextResponse.json({ metrics, trend, classTrend, levels, classes, atRisk, topReaders, books });
  } catch {
    return NextResponse.json({ error: 'Failed to fetch analytics' }, { status: 500 });
  }
}
