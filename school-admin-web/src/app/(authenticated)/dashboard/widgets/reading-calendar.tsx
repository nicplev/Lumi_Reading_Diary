'use client';

import { useReadingCalendar, type ReadingCalendarDay } from '@/lib/hooks/use-reading-calendar';

// 0 = none, then increasing Lumi Blue intensity (dashboard data-viz).
const LEVEL_COLORS = ['#EDEAE3', '#C8E8F1', '#9BD7EA', '#56C8E6'];

/** Parse a yyyy-mm-dd key as a local date (avoids UTC-vs-local off-by-one). */
function parseLocal(date: string): Date {
  const [y, m, d] = date.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/**
 * A GitHub-style heatmap of daily reading across the teacher's classes. Self-
 * fetches via useReadingCalendar so the wider scan behind it only runs when this
 * widget is actually shown.
 */
export function ReadingCalendar() {
  const { data, isLoading } = useReadingCalendar();

  if (isLoading) {
    return (
      <p className="text-sm text-muted h-full flex items-center">Loading reading calendar…</p>
    );
  }

  const days = data ?? [];
  if (days.length === 0) {
    return <p className="text-sm text-muted h-full flex items-center">No reading activity yet.</p>;
  }

  const max = Math.max(...days.map((d) => d.count), 1);
  const level = (count: number) => {
    if (count === 0) return 0;
    const ratio = count / max;
    if (ratio > 0.66) return 3;
    if (ratio > 0.33) return 2;
    return 1;
  };

  // Pad leading cells so the first column aligns to the weekday (Mon at top).
  const firstDow = (parseLocal(days[0].date).getDay() + 6) % 7;
  const cells: (ReadingCalendarDay | null)[] = [...Array(firstDow).fill(null), ...days];

  const fmt = (key: string) =>
    parseLocal(key).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
  const weeks = Math.round(days.length / 7);
  const rangeLabel = `${fmt(days[0].date)} – ${fmt(days[days.length - 1].date)}`;

  return (
    <div className="h-full flex flex-col justify-center gap-3">
      <div className="flex items-center justify-between gap-2">
        <span className="text-xs font-semibold text-ink">Last {weeks} weeks</span>
        <span className="text-xs text-muted">{rangeLabel}</span>
      </div>
      <div className="grid grid-flow-col gap-1" style={{ gridTemplateRows: 'repeat(7, 1fr)' }}>
        {cells.map((cell, i) =>
          cell === null ? (
            <div key={`pad-${i}`} className="w-3.5 h-3.5" />
          ) : (
            <div
              key={cell.date}
              title={`${cell.date}: ${cell.count} log${cell.count === 1 ? '' : 's'}`}
              className="w-3.5 h-3.5 rounded-[3px]"
              style={{ backgroundColor: LEVEL_COLORS[level(cell.count)] }}
            />
          )
        )}
      </div>
      <div className="flex items-center justify-between gap-1.5 text-xs text-muted">
        <span>Reading logs / day</span>
        <span className="inline-flex items-center gap-1.5">
          <span>Fewer</span>
          {LEVEL_COLORS.map((c) => (
            <span key={c} className="w-3 h-3 rounded-[3px]" style={{ backgroundColor: c }} />
          ))}
          <span>More</span>
        </span>
      </div>
    </div>
  );
}
