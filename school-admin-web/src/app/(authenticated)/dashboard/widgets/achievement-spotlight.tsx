'use client';

import Link from 'next/link';
import { Icon } from '@/components/lumi/icon';

// Rarity colours mirror the app's AchievementRarity palette (same as the
// per-student achievements card).
const RARITY: Record<string, { label: string; color: string }> = {
  common: { label: 'Common', color: '#CD7F32' },
  uncommon: { label: 'Uncommon', color: '#9CA3AF' },
  rare: { label: 'Rare', color: '#E0A100' },
  epic: { label: 'Epic', color: '#A855F7' },
  legendary: { label: 'Legendary', color: '#EC4899' },
};

interface SpotlightItem {
  studentId: string;
  studentName: string;
  name: string;
  icon: string;
  rarity: string;
  earnedAt: string | null;
}

/** The most recently earned achievements across the teacher's students. */
export function AchievementSpotlight({ items }: { items: SpotlightItem[] }) {
  if (items.length === 0) {
    return (
      <div className="h-full flex flex-col items-center justify-center text-center py-4">
        <span className="text-text-secondary/40 mb-2">
          <Icon name="emoji_events" size={28} />
        </span>
        <p className="text-sm text-text-secondary">No achievements earned recently.</p>
      </div>
    );
  }

  return (
    <ul className="space-y-2.5">
      {items.map((a, i) => {
        const rarity = RARITY[a.rarity] ?? RARITY.common;
        return (
          <li key={`${a.studentId}-${a.name}-${i}`}>
            <Link
              href={`/students/${a.studentId}`}
              className="flex items-center gap-3 hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
            >
              <span className="text-2xl leading-none flex-shrink-0">{a.icon}</span>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <p className="text-sm font-semibold text-charcoal truncate">{a.name}</p>
                  <span
                    style={{ backgroundColor: rarity.color }}
                    className="text-white text-[10px] font-semibold px-2 py-0.5 rounded-[var(--radius-pill)] flex-shrink-0"
                  >
                    {rarity.label}
                  </span>
                </div>
                <p className="text-xs text-text-secondary truncate">{a.studentName}</p>
              </div>
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
