'use client';

import { useMemo, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Tabs } from '@/components/lumi/tabs';
import { Icon } from '@/components/lumi/icon';
import { EmptyState } from '@/components/lumi/empty-state';
import { SearchInput } from '@/components/lumi/search-input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { CommentThread } from './comment-thread';
import { LogMedia } from './log-media';
import { useReadingLogs } from '@/lib/hooks/use-reading-logs';

const FEELING_META: Record<string, { label: string; emoji: string }> = {
  hard: { label: 'Hard', emoji: '😣' },
  tricky: { label: 'Tricky', emoji: '😕' },
  okay: { label: 'Okay', emoji: '🙂' },
  good: { label: 'Good', emoji: '😀' },
  great: { label: 'Great', emoji: '🤩' },
};

const STATUS_DOT: Record<string, string> = {
  completed: 'bg-mint-green',
  partial: 'bg-soft-yellow',
  skipped: 'bg-error',
  pending: 'bg-divider',
};

type DateFilter = 'all' | 'week' | 'month';

const DATE_FILTERS: { value: DateFilter; label: string }[] = [
  { value: 'all', label: 'All time' },
  { value: 'week', label: 'Last 7 days' },
  { value: 'month', label: 'This month' },
];

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

export function ReadingHistorySection({ studentId }: { studentId: string }) {
  const { data: logs, isLoading } = useReadingLogs(studentId);
  const [mode, setMode] = useState<'logs' | 'books'>('logs');
  const [dateFilter, setDateFilter] = useState<DateFilter>('all');
  const [feelings, setFeelings] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const toggleFeeling = (key: string) =>
    setFeelings((prev) => (prev.includes(key) ? prev.filter((f) => f !== key) : [...prev, key]));

  const filtered = useMemo(() => {
    let list = logs ?? [];
    const now = Date.now();
    if (dateFilter === 'week') {
      const cutoff = now - 7 * 24 * 60 * 60 * 1000;
      list = list.filter((l) => new Date(l.date).getTime() >= cutoff);
    } else if (dateFilter === 'month') {
      const d = new Date();
      const startOfMonth = new Date(d.getFullYear(), d.getMonth(), 1).getTime();
      list = list.filter((l) => new Date(l.date).getTime() >= startOfMonth);
    }
    if (feelings.length > 0) {
      list = list.filter((l) => l.childFeeling && feelings.includes(l.childFeeling));
    }
    const q = search.trim().toLowerCase();
    if (q) {
      list = list.filter((l) => l.bookTitles.some((t) => t.toLowerCase().includes(q)));
    }
    return list;
  }, [logs, dateFilter, feelings, search]);

  const bookSummary = useMemo(() => {
    const map = new Map<string, { title: string; sessions: number; minutes: number }>();
    for (const l of filtered) {
      for (const t of l.bookTitles) {
        const key = t.toLowerCase();
        const cur = map.get(key) ?? { title: t, sessions: 0, minutes: 0 };
        cur.sessions += 1;
        cur.minutes += l.minutesRead;
        map.set(key, cur);
      }
    }
    return [...map.values()].sort((a, b) => b.sessions - a.sessions);
  }, [filtered]);

  return (
    <div className="mt-6">
      <Card>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-bold text-charcoal">Reading History</h2>
          {logs && logs.length > 0 && (
            <span className="text-sm text-text-secondary">
              {logs.length} session{logs.length === 1 ? '' : 's'}
            </span>
          )}
        </div>

        <Tabs
          tabs={[
            { id: 'logs', label: 'Logs' },
            { id: 'books', label: 'Books' },
          ]}
          activeTab={mode}
          onChange={(id) => setMode(id as 'logs' | 'books')}
        />

        <div className="flex flex-col gap-3 mt-4 mb-4">
          <div className="flex flex-wrap gap-2">
            {DATE_FILTERS.map((f) => (
              <FilterChip
                key={f.value}
                label={f.label}
                selected={dateFilter === f.value}
                onClick={() => setDateFilter(f.value)}
              />
            ))}
          </div>
          <div className="flex flex-wrap gap-2">
            {Object.entries(FEELING_META).map(([key, m]) => (
              <FilterChip
                key={key}
                label={`${m.emoji} ${m.label}`}
                selected={feelings.includes(key)}
                onClick={() => toggleFeeling(key)}
              />
            ))}
          </div>
          <SearchInput value={search} onChange={setSearch} placeholder="Search by book title…" />
        </div>

        {isLoading ? (
          <p className="text-sm text-text-secondary py-6 text-center">Loading reading history…</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<Icon name="menu_book" size={40} />}
            title={(logs ?? []).length === 0 ? 'No reading logged yet' : 'No sessions match your filters'}
            description={
              (logs ?? []).length === 0
                ? 'Reading sessions logged by families or staff will appear here.'
                : 'Try clearing the filters or search.'
            }
          />
        ) : mode === 'logs' ? (
          <ul className="divide-y divide-divider">
            {filtered.map((log) => {
              const isExpanded = expandedId === log.id;
              const feeling = log.childFeeling ? FEELING_META[log.childFeeling] : null;
              return (
                <li key={log.id} className="py-3">
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : log.id)}
                    className="w-full text-left"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex items-start gap-3">
                        <span
                          className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${STATUS_DOT[log.status] ?? 'bg-divider'}`}
                        />
                        <div>
                          <p className="font-semibold text-charcoal">
                            {log.bookTitles.join(', ') || 'Reading'}
                          </p>
                          <p className="text-xs text-text-secondary">
                            {formatDate(log.date)} · {log.minutesRead} min
                            {log.loggedByRole === 'teacher' && log.loggedByLabel
                              ? ` · ${log.loggedByLabel}`
                              : ''}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 flex-shrink-0">
                        {feeling && <span title={feeling.label}>{feeling.emoji}</span>}
                        {log.hasComprehensionAudio && (
                          <Icon name="mic" size={16} className="text-text-secondary" />
                        )}
                        <span className="relative inline-flex items-center">
                          <Icon name="chat_bubble" size={16} className="text-text-secondary" />
                          {log.hasUnread && (
                            <span className="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-mint-green" />
                          )}
                        </span>
                      </div>
                    </div>
                  </button>
                  {isExpanded && (
                    <>
                      <LogMedia
                        logId={log.id}
                        hasAudio={log.hasComprehensionAudio}
                        durationSec={log.comprehensionAudioDurationSec}
                      />
                      <CommentThread logId={log.id} hasUnread={log.hasUnread} />
                    </>
                  )}
                </li>
              );
            })}
          </ul>
        ) : (
          <ul className="divide-y divide-divider">
            {bookSummary.map((b) => (
              <li key={b.title} className="py-3 flex items-center justify-between gap-3">
                <span className="font-semibold text-charcoal">{b.title}</span>
                <span className="text-xs text-text-secondary whitespace-nowrap">
                  {b.sessions} session{b.sessions === 1 ? '' : 's'} · {b.minutes} min
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}
