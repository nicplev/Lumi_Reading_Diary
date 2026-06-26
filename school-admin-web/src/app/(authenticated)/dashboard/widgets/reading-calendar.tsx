'use client';

import { useReadingCalendar, type ReadingCalendarDay } from '@/lib/hooks/use-reading-calendar';

// 0 = none, then increasing pink intensity.
const LEVEL_COLORS = ['#F3F4F6', '#FFD6DC', '#FFA9B5', '#FF8698'];

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
      <p className="text-sm text-text-secondary h-full flex items-center">Loading reading calendar…</p>
    );
  }

  const days = data ?? [];
  if (days.length === 0) {
    return <p className="text-sm text-text-secondary h-full flex items-center">No reading activity yet.</p>;
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

  return (
    <div className="h-full flex flex-col justify-center gap-3">
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
      <div className="flex items-center justify-end gap-1.5 text-xs text-text-secondary">
        <span>Less</span>
        {LEVEL_COLORS.map((c) => (
          <span key={c} className="w-3 h-3 rounded-[3px]" style={{ backgroundColor: c }} />
        ))}
        <span>More</span>
      </div>
    </div>
  );
}
