import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import {
  getReadingMetrics,
  getEngagementTrend,
  getLevelDistribution,
  getClassComparison,
  getAtRiskStudents,
  getTopReaders,
  getPopularBooks,
} from '@/lib/firestore/analytics';
import { AnalyticsPage } from './analytics-page';

export default async function AnalyticsRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const [metrics, trend, levels, classes, atRisk, topReaders, books] = await Promise.all([
    getReadingMetrics(session.schoolId, 30),
    getEngagementTrend(session.schoolId, 30),
    getLevelDistribution(session.schoolId),
    getClassComparison(session.schoolId),
    getAtRiskStudents(session.schoolId, 7),
    getTopReaders(session.schoolId, 10),
    getPopularBooks(session.schoolId, 30, 15),
  ]);

  return (
    <AnalyticsPage
      metrics={metrics}
      trend={trend}
      levels={levels}
      classes={classes}
      atRisk={atRisk}
      topReaders={topReaders}
      books={books}
    />
  );
}
