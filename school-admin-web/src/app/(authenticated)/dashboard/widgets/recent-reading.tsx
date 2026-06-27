'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Avatar } from '@/components/lumi/avatar';

function timeAgo(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

/** Renders the relative time client-side only, so SSR and hydration match. */
function RelTime({ iso }: { iso: string }) {
  const [label, setLabel] = useState('');
  useEffect(() => {
    setLabel(timeAgo(iso));
  }, [iso]);
  return <span className="text-xs text-muted whitespace-nowrap">{label}</span>;
}

interface RecentReadingItem {
  logId: string;
  studentId: string;
  studentName: string;
  books: string[];
  minutes: number;
  at: string;
  characterId?: string;
}

/** A live feed of the latest reading logged across the teacher's classes. */
export function RecentReading({ items }: { items: RecentReadingItem[] }) {
  if (items.length === 0) {
    return (
      <p className="text-sm text-muted h-full flex items-center">
        No reading logged yet this week.
      </p>
    );
  }

  return (
    <ul className="space-y-2.5 max-h-72 overflow-y-auto -mr-1 pr-1">
      {items.map((it) => (
        <li key={it.logId}>
          <Link
            href={`/students/${it.studentId}`}
            className="flex items-start gap-2 hover:bg-cream rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
          >
            <Avatar name={it.studentName} characterId={it.characterId} size="sm" className="flex-shrink-0 mt-0.5" />
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-ink truncate">{it.studentName}</p>
              <p className="text-xs text-muted truncate">
                {it.books.length > 0 ? it.books.join(', ') : 'Reading'} · {it.minutes} min
              </p>
            </div>
            <RelTime iso={it.at} />
          </Link>
        </li>
      ))}
    </ul>
  );
}
