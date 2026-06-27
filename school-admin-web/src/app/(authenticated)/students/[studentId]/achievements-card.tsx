'use client';

import { Card } from '@/components/lumi/card';
import { Icon } from '@/components/lumi/icon';
import { useStudentAchievements } from '@/lib/hooks/use-achievements';

// Rarity colours mirror the app's AchievementRarity palette.
const RARITY: Record<string, { label: string; color: string }> = {
  common: { label: 'Common', color: '#CD7F32' },
  uncommon: { label: 'Uncommon', color: '#9CA3AF' },
  rare: { label: 'Rare', color: '#E0A100' },
  epic: { label: 'Epic', color: '#A855F7' },
  legendary: { label: 'Legendary', color: '#EC4899' },
};

function formatDate(iso: string | null): string {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

export function AchievementsCard({ studentId }: { studentId: string }) {
  const { data, isLoading } = useStudentAchievements(studentId);

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-bold text-ink">Achievements</h2>
        {data && data.length > 0 && (
          <span className="text-sm text-muted">{data.length} earned</span>
        )}
      </div>

      {isLoading ? (
        <p className="text-sm text-muted">Loading…</p>
      ) : (data ?? []).length === 0 ? (
        <div className="flex flex-col items-center justify-center py-6 text-center">
          <span className="text-muted/40 mb-2">
            <Icon name="emoji_events" size={32} />
          </span>
          <p className="text-sm text-muted">No achievements earned yet.</p>
        </div>
      ) : (
        <div className="space-y-2.5">
          {(data ?? []).map((a, i) => {
            const rarity = RARITY[a.rarity] ?? RARITY.common;
            return (
              <div key={`${a.id}-${i}`} className="flex items-center gap-3">
                <span className="text-2xl leading-none">{a.icon}</span>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="font-semibold text-ink text-sm">{a.name}</p>
                    <span
                      style={{ backgroundColor: rarity.color }}
                      className="text-white text-[10px] font-semibold px-2 py-0.5 rounded-[var(--radius-pill)]"
                    >
                      {rarity.label}
                    </span>
                  </div>
                  <p className="text-xs text-muted">
                    {a.description}
                    {a.earnedAt ? ` · ${formatDate(a.earnedAt)}` : ''}
                  </p>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}
