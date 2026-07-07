'use client';

import { useQuery } from '@tanstack/react-query';
import type { WeeklyEngagement } from '@/lib/firestore/dashboard';

/**
 * Weekly engagement for the dashboard chart, keyed by Monday-anchored week
 * offset (0 = this week, -1 = last week). The dashboard page server-renders
 * this-week's data, so pass it as `initialData` for offset 0 — only other
 * offsets trigger a fetch.
 */
export function useWeeklyEngagement(offset: number, initialThisWeek?: WeeklyEngagement[]) {
  return useQuery<WeeklyEngagement[]>({
    queryKey: ['weekly-engagement', offset],
    queryFn: async () => {
      const res = await fetch(`/api/dashboard/weekly-engagement?offset=${offset}`);
      if (!res.ok) throw new Error('Failed to load weekly engagement');
      return res.json();
    },
    initialData: offset === 0 ? initialThisWeek : undefined,
    staleTime: 5 * 60 * 1000,
  });
}
