'use client';

import { useQuery } from '@tanstack/react-query';
import type {
  ReadingMetrics,
  EngagementPoint,
  LevelBucket,
  ClassComparisonRow,
  AtRiskStudent,
  TopReader,
  PopularBook,
} from '@/lib/firestore/analytics';

export interface AnalyticsData {
  metrics: ReadingMetrics;
  trend: EngagementPoint[];
  levels: LevelBucket[];
  classes: ClassComparisonRow[];
  atRisk: AtRiskStudent[];
  topReaders: TopReader[];
  books: PopularBook[];
}

export type AnalyticsPeriod = '5days' | 'month' | 'term' | 'year';

export function useAnalytics(period: AnalyticsPeriod, termKey?: string) {
  const params = new URLSearchParams({ period });
  if (termKey) params.set('termKey', termKey);

  return useQuery<AnalyticsData>({
    queryKey: ['analytics', period, termKey ?? null],
    queryFn: async () => {
      const res = await fetch(`/api/analytics?${params}`);
      if (!res.ok) throw new Error('Failed to fetch analytics');
      return res.json();
    },
    staleTime: 2 * 60 * 1000,
  });
}
