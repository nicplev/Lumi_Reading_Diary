'use client';

import { useQuery } from '@tanstack/react-query';
import type { ClassReport } from '@/lib/firestore/reports';

export type { ClassReport } from '@/lib/firestore/reports';

/**
 * Class reading report for a date range. `from`/`to` are ISO date strings
 * (YYYY-MM-DD); the API fills inclusive day boundaries.
 */
export function useClassReport(classId: string, from: string, to: string) {
  return useQuery<ClassReport>({
    queryKey: ['class-report', classId, from, to],
    queryFn: async () => {
      const params = new URLSearchParams({ classId, from, to });
      const res = await fetch(`/api/reports?${params}`);
      if (!res.ok) throw new Error('Failed to load report');
      return res.json();
    },
    enabled: !!classId && !!from && !!to,
    staleTime: 60 * 1000,
  });
}
