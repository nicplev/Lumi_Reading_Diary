'use client';

import { useQuery } from '@tanstack/react-query';

export interface ReadingCalendarDay {
  date: string; // yyyy-mm-dd
  count: number;
}

/**
 * Daily reading-log counts for the dashboard heatmap. Fetched only when the
 * calendar widget is mounted (i.e. visible), so the heavier multi-week scan
 * behind it doesn't run on every dashboard load.
 */
export function useReadingCalendar() {
  return useQuery<ReadingCalendarDay[]>({
    queryKey: ['reading-calendar'],
    queryFn: async () => {
      const res = await fetch('/api/dashboard/reading-calendar');
      if (!res.ok) throw new Error('Failed to load reading calendar');
      return res.json();
    },
    staleTime: 5 * 60 * 1000,
  });
}
