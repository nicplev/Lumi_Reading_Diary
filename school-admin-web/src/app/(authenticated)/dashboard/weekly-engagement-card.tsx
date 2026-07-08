'use client';

import { useEffect, useState } from 'react';
import { WeeklyChart } from './weekly-chart';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useWeeklyEngagement } from '@/lib/hooks/use-weekly-engagement';
import type { WeeklyEngagement } from '@/lib/firestore/dashboard';

const TIMEFRAMES: { offset: number; label: string }[] = [
  { offset: 0, label: 'This week' },
  { offset: -1, label: 'Last week' },
  { offset: -2, label: '2 weeks ago' },
];

/**
 * The dashboard weekly chart plus a timeframe selector. Monday morning the
 * current week is empty — a teacher doing the "who read last week?" ritual
 * flips to Last week instead of staring at a blank chart. The choice is
 * remembered per teacher.
 */
export function WeeklyEngagementCard({
  initialThisWeek,
  storageKey,
}: {
  initialThisWeek: WeeklyEngagement[];
  storageKey: string;
}) {
  const [offset, setOffset] = useState(0);

  // Restore the remembered timeframe after mount (SSR-safe).
  useEffect(() => {
    try {
      const saved = Number(localStorage.getItem(storageKey));
      if (TIMEFRAMES.some((t) => t.offset === saved)) setOffset(saved);
    } catch {
      /* localStorage unavailable — keep the default */
    }
  }, [storageKey]);

  const select = (next: number) => {
    setOffset(next);
    try {
      localStorage.setItem(storageKey, String(next));
    } catch {
      /* ignore */
    }
  };

  const { data, isLoading, isError } = useWeeklyEngagement(offset, initialThisWeek);

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-1.5">
        {TIMEFRAMES.map((t) => (
          <FilterChip
            key={t.offset}
            label={t.label}
            selected={offset === t.offset}
            onClick={() => select(t.offset)}
          />
        ))}
      </div>
      {isError ? (
        <p className="text-sm text-muted h-[180px] flex items-center">
          Couldn&apos;t load that week — try again.
        </p>
      ) : isLoading || !data ? (
        <p className="text-sm text-muted h-[180px] flex items-center">Loading…</p>
      ) : (
        <WeeklyChart data={data} />
      )}
    </div>
  );
}
