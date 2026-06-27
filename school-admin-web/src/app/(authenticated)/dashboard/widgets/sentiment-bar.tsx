'use client';

import { FEELINGS, FEELING_ORDER } from '@/lib/feelings';
import { FeelingBlob } from '@/components/lumi/feeling-blob';

/** How children felt about their reading this week — a stacked bar + tally.
 *  Uses the feeling blobs (concern → confident) shared with the reading history. */
export function SentimentBar({ sentiment }: { sentiment: { feeling: string; count: number }[] }) {
  const byFeeling = new Map(sentiment.map((s) => [s.feeling, s.count]));
  const total = sentiment.reduce((sum, s) => sum + s.count, 0);

  if (total === 0) {
    return (
      <p className="text-sm text-text-secondary h-full flex items-center">
        No reading feelings logged yet this week.
      </p>
    );
  }

  return (
    <div className="h-full flex flex-col justify-center gap-4">
      <div className="flex h-3 w-full overflow-hidden rounded-[var(--radius-pill)]">
        {FEELING_ORDER.map((key) => {
          const count = byFeeling.get(key) ?? 0;
          if (count === 0) return null;
          return (
            <div
              key={key}
              style={{ width: `${(count / total) * 100}%`, backgroundColor: FEELINGS[key].color }}
              title={`${FEELINGS[key].label}: ${count}`}
            />
          );
        })}
      </div>
      <div className="grid grid-cols-5 gap-1 text-center">
        {FEELING_ORDER.map((key) => {
          const count = byFeeling.get(key) ?? 0;
          return (
            <div key={key} className="flex flex-col items-center">
              <FeelingBlob feeling={key} size={28} />
              <span className="text-sm font-bold text-charcoal mt-1">{count}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
