'use client';

// Mirrors the 😣😕🙂😀🤩 scale used in the student reading history, coloured
// concern → confident.
const SENTIMENT: Record<string, { label: string; emoji: string; color: string }> = {
  hard: { label: 'Hard', emoji: '😣', color: '#EF4444' },
  tricky: { label: 'Tricky', emoji: '😕', color: '#F97316' },
  okay: { label: 'Okay', emoji: '🙂', color: '#FBBF24' },
  good: { label: 'Good', emoji: '😀', color: '#34D399' },
  great: { label: 'Great', emoji: '🤩', color: '#10B981' },
};
const ORDER = ['hard', 'tricky', 'okay', 'good', 'great'];

/** How children felt about their reading this week — a stacked bar + tally. */
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
        {ORDER.map((key) => {
          const count = byFeeling.get(key) ?? 0;
          if (count === 0) return null;
          return (
            <div
              key={key}
              style={{ width: `${(count / total) * 100}%`, backgroundColor: SENTIMENT[key].color }}
              title={`${SENTIMENT[key].label}: ${count}`}
            />
          );
        })}
      </div>
      <div className="grid grid-cols-5 gap-1 text-center">
        {ORDER.map((key) => {
          const count = byFeeling.get(key) ?? 0;
          return (
            <div key={key} className="flex flex-col items-center">
              <span className="text-lg leading-none" title={SENTIMENT[key].label}>
                {SENTIMENT[key].emoji}
              </span>
              <span className="text-sm font-bold text-charcoal mt-1">{count}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
