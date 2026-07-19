'use client';

import { useMemo, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { QueryError } from '@/components/lumi/query-error';
import { Tabs } from '@/components/lumi/tabs';
import { Icon } from '@/components/lumi/icon';
import { EmptyState } from '@/components/lumi/empty-state';
import { SearchInput } from '@/components/lumi/search-input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { Button } from '@/components/lumi/button';
import { FeelingBlob } from '@/components/lumi/feeling-blob';
import { FEELINGS, FEELING_ORDER } from '@/lib/feelings';
import { CommentThread } from './comment-thread';
import { LogMedia } from './log-media';
import { useReadingLogs } from '@/lib/hooks/use-reading-logs';
import { useSchool } from '@/lib/hooks/use-school';

const STATUS_DOT: Record<string, string> = {
  completed: 'bg-lumi-green',
  partial: 'bg-lumi-yellow',
  skipped: 'bg-error',
  pending: 'bg-rule',
};

type Preset = '7d' | '60d' | 'custom';

const DAY_MS = 24 * 60 * 60 * 1000;

// <input type="date"> speaks YYYY-MM-DD; convert to/from local Date parts so the
// window matches the viewer's calendar day rather than UTC.
function toDateInput(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${m}-${day}`;
}

function dateInputToISO(value: string, endOfDay: boolean): string {
  const [y, m, d] = value.split('-').map(Number);
  return new Date(
    y,
    m - 1,
    d,
    endOfDay ? 23 : 0,
    endOfDay ? 59 : 0,
    endOfDay ? 59 : 0,
    endOfDay ? 999 : 0,
  ).toISOString();
}

function startOfDaysAgo(days: number): string {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return new Date(d.getTime() - days * DAY_MS).toISOString();
}

function endOfToday(): string {
  const d = new Date();
  d.setHours(23, 59, 59, 999);
  return d.toISOString();
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
  });
}

export function ReadingHistorySection({ studentId }: { studentId: string }) {
  const [mode, setMode] = useState<'logs' | 'books'>('logs');
  // Default to the last 7 days — a prolific reader can have hundreds of logs, and
  // fetching them all buries the rest of the profile under endless scroll. Wider
  // windows load on demand; the server hard-caps history at 2 years.
  const [preset, setPreset] = useState<Preset>('7d');
  const [customFrom, setCustomFrom] = useState(toDateInput(new Date(Date.now() - 60 * DAY_MS)));
  const [customTo, setCustomTo] = useState(toDateInput(new Date()));
  const [appliedCustom, setAppliedCustom] = useState<{ from: string; to: string } | null>(null);
  const [feelings, setFeelings] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const { data: school } = useSchool();
  const audioSettings = school?.settings?.comprehensionRecording as
    | { enabled?: boolean }
    | undefined;
  const audioPlaybackEnabled =
    school?.platformFlags?.comprehensionRecordingEnabled === true &&
    audioSettings?.enabled === true;

  // Date inputs are bounded to [2 years ago, today] — the same hard floor the
  // server enforces, so the picker can never request data that's been cleaned up.
  const todayInput = toDateInput(new Date());
  const minInput = (() => {
    const d = new Date();
    d.setFullYear(d.getFullYear() - 2);
    return toDateInput(d);
  })();

  const range = useMemo(() => {
    if (preset === '7d') return { from: startOfDaysAgo(7), to: endOfToday() };
    if (preset === '60d') return { from: startOfDaysAgo(60), to: endOfToday() };
    return appliedCustom ?? { from: startOfDaysAgo(7), to: endOfToday() };
  }, [preset, appliedCustom]);

  const { data: logs, isLoading, isFetching, isError, refetch } = useReadingLogs(studentId, range);

  const canApplyCustom = !!customFrom && !!customTo && customFrom <= customTo;
  const applyCustom = () => {
    if (!canApplyCustom) return;
    setAppliedCustom({
      from: dateInputToISO(customFrom, false),
      to: dateInputToISO(customTo, true),
    });
  };

  const toggleFeeling = (key: string) =>
    setFeelings((prev) => (prev.includes(key) ? prev.filter((f) => f !== key) : [...prev, key]));

  // Date windowing happens server-side (see `range`); here we only narrow by
  // feeling + book title within whatever window was fetched.
  const filtered = useMemo(() => {
    let list = logs ?? [];
    if (feelings.length > 0) {
      list = list.filter((l) => l.childFeeling && feelings.includes(l.childFeeling));
    }
    const q = search.trim().toLowerCase();
    if (q) {
      list = list.filter((l) => l.bookTitles.some((t) => t.toLowerCase().includes(q)));
    }
    return list;
  }, [logs, feelings, search]);

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
          <h2 className="text-lg font-bold text-ink">Reading History</h2>
          {isFetching && !isLoading ? (
            <span className="text-sm text-muted">Updating…</span>
          ) : logs && logs.length > 0 ? (
            <span className="text-sm text-muted">
              {logs.length} session{logs.length === 1 ? '' : 's'}
            </span>
          ) : null}
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
            <FilterChip label="Last 7 days" selected={preset === '7d'} onClick={() => setPreset('7d')} />
            <FilterChip label="Last 60 days" selected={preset === '60d'} onClick={() => setPreset('60d')} />
            <FilterChip label="Custom range" selected={preset === 'custom'} onClick={() => setPreset('custom')} />
          </div>
          {preset === 'custom' && (
            <div className="rounded-[var(--radius-md)] border border-rule bg-cream p-3 flex flex-col gap-3">
              <div className="flex flex-wrap items-end gap-3">
                <label className="flex flex-col gap-1 text-xs font-medium text-muted">
                  From
                  <input
                    type="date"
                    value={customFrom}
                    min={minInput}
                    max={customTo || todayInput}
                    onChange={(e) => setCustomFrom(e.target.value)}
                    className="rounded-[var(--radius-sm)] border border-rule bg-paper px-2.5 py-1.5 text-sm text-ink"
                  />
                </label>
                <label className="flex flex-col gap-1 text-xs font-medium text-muted">
                  To
                  <input
                    type="date"
                    value={customTo}
                    min={customFrom || minInput}
                    max={todayInput}
                    onChange={(e) => setCustomTo(e.target.value)}
                    className="rounded-[var(--radius-sm)] border border-rule bg-paper px-2.5 py-1.5 text-sm text-ink"
                  />
                </label>
                <Button variant="outline" onClick={applyCustom} disabled={!canApplyCustom}>
                  Load
                </Button>
              </div>
              <p className="text-xs text-muted">
                Pick any range within the last 2 years. Reading history older than 2 years isn’t kept.
              </p>
            </div>
          )}
          <div className="flex flex-wrap gap-2">
            {FEELING_ORDER.map((key) => (
              <FilterChip
                key={key}
                label={
                  <span className="inline-flex items-center gap-1.5">
                    <FeelingBlob feeling={key} size={16} />
                    {FEELINGS[key].label}
                  </span>
                }
                selected={feelings.includes(key)}
                onClick={() => toggleFeeling(key)}
              />
            ))}
          </div>
          <SearchInput value={search} onChange={setSearch} placeholder="Search by book title…" />
        </div>

        {isError ? (
          <QueryError
            message="We couldn't load this reading history."
            onRetry={() => refetch()}
          />
        ) : isLoading ? (
          <p className="text-sm text-muted py-6 text-center">Loading reading history…</p>
        ) : filtered.length === 0 ? (
          <EmptyState
            icon={<Icon name="menu_book" size={40} />}
            title={(logs ?? []).length === 0 ? 'No reading in this range' : 'No sessions match your filters'}
            description={
              (logs ?? []).length === 0
                ? 'Try the last 60 days or a custom date range to look further back.'
                : 'Try clearing the filters or search.'
            }
          />
        ) : mode === 'logs' ? (
          <ul className="divide-y divide-rule">
            {filtered.map((log) => {
              const isExpanded = expandedId === log.id;
              return (
                <li key={log.id} className="py-3">
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : log.id)}
                    className="w-full text-left"
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex items-start gap-3">
                        <span
                          className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${STATUS_DOT[log.status] ?? 'bg-rule'}`}
                        />
                        <div>
                          <p className="font-semibold text-ink">
                            {log.bookTitles.join(', ') || 'Reading'}
                          </p>
                          <p className="text-xs text-muted">
                            {formatDate(log.date)} · {log.minutesRead} min
                            {log.loggedByRole === 'teacher' && log.loggedByLabel
                              ? ` · ${log.loggedByLabel}`
                              : ''}
                          </p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2 flex-shrink-0">
                        {log.childFeeling && <FeelingBlob feeling={log.childFeeling} size={18} />}
                        {audioPlaybackEnabled && log.hasComprehensionAudio && (
                          <Icon name="mic" size={16} className="text-muted" />
                        )}
                        <span className="relative inline-flex items-center">
                          <Icon name="chat_bubble" size={16} className="text-muted" />
                          {log.hasUnread && (
                            <span className="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-lumi-green" />
                          )}
                        </span>
                      </div>
                    </div>
                  </button>
                  {isExpanded && (
                    <>
                      <LogMedia
                        logId={log.id}
                        hasAudio={audioPlaybackEnabled && log.hasComprehensionAudio}
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
          <ul className="divide-y divide-rule">
            {bookSummary.map((b) => (
              <li key={b.title} className="py-3 flex items-center justify-between gap-3">
                <span className="font-semibold text-ink">{b.title}</span>
                <span className="text-xs text-muted whitespace-nowrap">
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
