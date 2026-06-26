'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';

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
  return <span className="text-xs text-text-secondary whitespace-nowrap">{label}</span>;
}

interface RecentReadingItem {
  logId: string;
  studentId: string;
  studentName: string;
  books: string[];
  minutes: number;
  at: string;
}

/** A live feed of the latest reading logged across the teacher's classes. */
export function RecentReading({ items }: { items: RecentReadingItem[] }) {
  if (items.length === 0) {
    return (
      <p className="text-sm text-text-secondary h-full flex items-center">
        No reading logged yet this week.
      </p>
    );
  }

  return (
    <ul className="space-y-2.5">
      {items.map((it) => (
        <li key={it.logId}>
          <Link
            href={`/students/${it.studentId}`}
            className="flex items-start justify-between gap-3 hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
          >
            <div className="min-w-0">
              <p className="text-sm font-medium text-charcoal truncate">{it.studentName}</p>
              <p className="text-xs text-text-secondary truncate">
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
