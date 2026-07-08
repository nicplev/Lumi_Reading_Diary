'use client';

import { useMemo, useState } from 'react';
import { Card } from '@/components/lumi/card';
import { QueryError } from '@/components/lumi/query-error';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { FilterChip } from '@/components/lumi/filter-chip';
import { EmptyState } from '@/components/lumi/empty-state';
import { useSchool } from '@/lib/hooks/use-school';
import { useClassReport } from '@/lib/hooks/use-reports';
import { useToast } from '@/components/lumi/toast';

function isoLocal(d: Date): string {
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

function isoToday(): string {
  return isoLocal(new Date());
}

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return isoLocal(d);
}

/** Monday of the week `offsetWeeks` from this one (0 = this week, -1 = last). */
function isoMonday(offsetWeeks: number): string {
  const d = new Date();
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + offsetWeeks * 7);
  return isoLocal(d);
}

/** Sunday ending the week `offsetWeeks` from this one. */
function isoSunday(offsetWeeks: number): string {
  const d = new Date();
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7) + offsetWeeks * 7 + 6);
  return isoLocal(d);
}

function formatDate(iso: string): string {
  return new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

// A preset without `to` runs through today.
const PRESETS: { key: string; label: string; from: () => string; to?: () => string }[] = [
  { key: 'this-week', label: 'This week', from: () => isoMonday(0) },
  { key: 'last-week', label: 'Last week', from: () => isoMonday(-1), to: () => isoSunday(-1) },
  { key: '30', label: 'Last 30 days', from: () => isoDaysAgo(30) },
  { key: '90', label: 'Last term (90 days)', from: () => isoDaysAgo(90) },
  { key: 'year', label: 'This year', from: () => `${new Date().getFullYear()}-01-01` },
];

interface ClassReportTabProps {
  classId: string;
  className: string;
  yearLevel?: string;
  /** False when the school has reading levels turned off — hides the
   *  reading-level distribution card (mirrors the roster's level UI gating). */
  levelsEnabled?: boolean;
}

// Bento tile / section-header colourways — soft brand tints with a matching
// dark accent for the icon. Keeps the report on the Lumi palette while giving
// each metric its own colour so the page reads as a lively dashboard, not a
// grey spreadsheet.
const TILE_STYLES = {
  blue: { tile: 'bg-tint-blue', icon: 'text-lumi-blue-dark' },
  green: { tile: 'bg-tint-green', icon: 'text-lumi-green-dark' },
  red: { tile: 'bg-tint-red', icon: 'text-lumi-red-dark' },
  yellow: { tile: 'bg-tint-yellow', icon: 'text-lumi-yellow-dark' },
  orange: { tile: 'bg-tint-orange', icon: 'text-lumi-orange' },
} as const;
type TileColor = keyof typeof TILE_STYLES;

function BentoMetric({
  label,
  value,
  icon,
  color,
}: {
  label: string;
  value: string | number;
  icon: string;
  color: TileColor;
}) {
  const s = TILE_STYLES[color];
  return (
    <div className={`rounded-[var(--radius-md)] p-4 ${s.tile}`}>
      <span
        className={`inline-flex items-center justify-center w-9 h-9 rounded-[var(--radius-sm)] bg-paper/70 ${s.icon} mb-2`}
      >
        <Icon name={icon} size={20} />
      </span>
      <p className="text-2xl font-extrabold text-ink leading-none">{value}</p>
      <p className="text-[11px] font-semibold text-ink/70 uppercase tracking-wide mt-1">{label}</p>
    </div>
  );
}

function SectionHeader({ icon, title, color }: { icon: string; title: string; color: TileColor }) {
  const s = TILE_STYLES[color];
  return (
    <div className="flex items-center gap-2.5 mb-4">
      <span className={`inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-sm)] ${s.tile} ${s.icon}`}>
        <Icon name={icon} size={18} />
      </span>
      <h2 className="text-lg font-extrabold text-ink">{title}</h2>
    </div>
  );
}

// Gold / silver / bronze for the top-3 readers; plain muted number after that.
const RANK_BADGE = ['bg-lumi-yellow text-ink', 'bg-rule text-ink', 'bg-lumi-orange text-white'];

export function ClassReportTab({ classId, className, yearLevel, levelsEnabled = true }: ClassReportTabProps) {
  const { data: school } = useSchool();
  const [from, setFrom] = useState(isoDaysAgo(30));
  const [to, setTo] = useState(isoToday());
  const [presetKey, setPresetKey] = useState('30');

  const { data: report, isLoading, isError, refetch } = useClassReport(classId, from, to);
  const { toast } = useToast();
  const [downloading, setDownloading] = useState(false);

  type SortKey = 'name' | 'minutes' | 'sessions' | 'readingDays' | 'metPct' | 'lastRead';
  const [sortKey, setSortKey] = useState<SortKey>('name');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('asc');
  const sortedStudents = useMemo(() => {
    if (!report) return [];
    const rows = [...report.students];
    rows.sort((a, b) => {
      const cmp =
        sortKey === 'name' ? a.name.localeCompare(b.name) :
        sortKey === 'lastRead' ? (a.lastRead ?? '').localeCompare(b.lastRead ?? '') :
        a[sortKey] - b[sortKey];
      return sortDir === 'asc' ? cmp : -cmp;
    });
    return rows;
  }, [report, sortKey, sortDir]);
  const toggleSort = (key: SortKey) => {
    if (key === sortKey) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      // Numbers read best largest-first on first click; names A→Z.
      setSortDir(key === 'name' ? 'asc' : 'desc');
    }
  };
  const sortMark = (key: SortKey) => (sortKey === key ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '');

  const handleDownloadPdf = async () => {
    if (!report) return;
    setDownloading(true);
    try {
      // Dynamic import keeps @react-pdf out of the main bundle until it's needed.
      const { downloadClassReportPdf } = await import('./class-report-pdf');
      await downloadClassReportPdf(report, school?.displayName || school?.name, levelsEnabled, school?.logoUrl);
    } catch {
      toast('Could not generate the PDF', 'error');
    } finally {
      setDownloading(false);
    }
  };

  const applyPreset = (key: string) => {
    const preset = PRESETS.find((p) => p.key === key);
    if (!preset) return;
    setPresetKey(key);
    setFrom(preset.from());
    setTo(preset.to ? preset.to() : isoToday());
  };

  const handleDownloadCsv = () => {
    if (!report) return;
    const esc = (v: string | number | null) => {
      const s = String(v ?? '');
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const rows = [
      ['Student', 'Minutes', 'Sessions', 'Reading days', 'Met target %', 'Last read', 'Reading level'],
      ...report.students.map((r) => [
        r.name, r.minutes, r.sessions, r.readingDays, r.metPct, r.lastRead ?? '', r.currentReadingLevel ?? '',
      ]),
    ];
    const csv = rows.map((row) => row.map(esc).join(',')).join('\r\n');
    const blob = new Blob([`﻿${csv}`], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const safeClass = (className || 'class').replace(/[^\w-]+/g, '-');
    a.href = url;
    a.download = `reading-report-${safeClass}-${from}-to-${to}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  };

  return (
    <div>
      {/* Controls — outside #class-report so they don't print */}
      <div className="flex flex-col gap-3 mb-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap gap-2">
            {PRESETS.map((p) => (
              <FilterChip
                key={p.key}
                label={p.label}
                selected={presetKey === p.key}
                onClick={() => applyPreset(p.key)}
              />
            ))}
          </div>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => window.print()} disabled={!report}>
              Print
            </Button>
            <Button variant="outline" size="sm" onClick={handleDownloadCsv} disabled={!report}>
              Export CSV
            </Button>
            <Button size="sm" onClick={handleDownloadPdf} loading={downloading} disabled={!report}>
              Download PDF
            </Button>
          </div>
        </div>
        <div className="flex flex-wrap items-end gap-3">
          <label className="text-sm">
            <span className="block text-xs font-semibold text-muted mb-1">From</span>
            <input
              type="date"
              value={from}
              max={to}
              onChange={(e) => {
                setFrom(e.target.value);
                setPresetKey('custom');
              }}
              className="px-3 py-2 rounded-[var(--radius-md)] border border-rule bg-paper text-ink text-sm focus:outline-none focus:ring-2 focus:ring-section/30"
            />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-semibold text-muted mb-1">To</span>
            <input
              type="date"
              value={to}
              min={from}
              max={isoToday()}
              onChange={(e) => {
                setTo(e.target.value);
                setPresetKey('custom');
              }}
              className="px-3 py-2 rounded-[var(--radius-md)] border border-rule bg-paper text-ink text-sm focus:outline-none focus:ring-2 focus:ring-section/30"
            />
          </label>
        </div>
      </div>

      {isError ? (
        <QueryError
          className="my-6"
          message="We couldn't build this class report."
          onRetry={() => refetch()}
        />
      ) : isLoading || !report ? (
        <p className="text-sm text-muted py-10 text-center">Building report…</p>
      ) : (
        <div id="class-report" className="space-y-6">
          {/* Branded report header — school logo on a section-accent band. */}
          <div className="rounded-[var(--radius-lg)] overflow-hidden border border-rule shadow-card">
            <div className="bg-section px-6 py-5 flex items-center gap-4">
              {school?.logoUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={school.logoUrl}
                  alt=""
                  className="w-14 h-14 rounded-[var(--radius-md)] bg-paper object-contain p-1 shrink-0"
                />
              ) : (
                <span className="inline-flex items-center justify-center w-14 h-14 rounded-[var(--radius-md)] bg-paper/20 text-on-section shrink-0">
                  <Icon name="local_fire_department" size={30} />
                </span>
              )}
              <div className="min-w-0">
                {school?.displayName || school?.name ? (
                  <p className="text-on-section/85 text-sm font-semibold truncate">
                    {school.displayName || school.name}
                  </p>
                ) : null}
                <h1 className="text-on-section text-2xl font-extrabold leading-tight">Class Reading Report</h1>
              </div>
              <span className="ml-auto hidden sm:inline-flex items-center gap-1.5 text-on-section/90 shrink-0">
                <Icon name="local_fire_department" size={18} />
                <span className="font-display font-extrabold tracking-tight">Lumi</span>
              </span>
            </div>
            <div className="bg-paper px-6 py-3 border-t border-rule">
              <p className="text-sm text-muted">
                {[className, yearLevel].filter(Boolean).join(' · ')} · {formatDate(from)} – {formatDate(to)}
              </p>
            </div>
          </div>

          {/* Headline metrics — colourful bento tiles */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <BentoMetric label="Students" value={report.totalStudents} icon="groups" color="blue" />
            <BentoMetric label="Active readers" value={report.activeReaders} icon="auto_stories" color="green" />
            <BentoMetric label="Engagement" value={`${report.engagementRate}%`} icon="trending_up" color="red" />
            <BentoMetric label="Met target" value={`${report.targetMetRate}%`} icon="flag" color="yellow" />
            <BentoMetric label="Total minutes" value={report.totalMinutes} icon="schedule" color="blue" />
            <BentoMetric label="Avg min / student" value={report.avgMinutesPerStudent} icon="timelapse" color="green" />
            <BentoMetric label="Reading days" value={report.totalReadingDays} icon="calendar_month" color="orange" />
            <BentoMetric label="Sessions" value={report.totalSessions} icon="menu_book" color="red" />
          </div>

          {/* Top readers */}
          <Card>
            <SectionHeader icon="emoji_events" title="Top readers" color="yellow" />
            {report.topReaders.length === 0 ? (
              <p className="text-sm text-muted">No reading recorded in this period.</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-muted border-b border-rule">
                    <th className="py-2 font-semibold w-10">#</th>
                    <th className="py-2 font-semibold">Student</th>
                    <th className="py-2 font-semibold text-right">Minutes</th>
                    <th className="py-2 font-semibold text-right">Days</th>
                    <th className="py-2 font-semibold text-right">Books</th>
                  </tr>
                </thead>
                <tbody>
                  {report.topReaders.map((r, i) => (
                    <tr key={r.id} className="border-b border-rule/60">
                      <td className="py-2">
                        <span
                          className={`inline-flex items-center justify-center w-6 h-6 rounded-full text-xs font-bold ${
                            i < 3 ? RANK_BADGE[i] : 'text-muted'
                          }`}
                        >
                          {i + 1}
                        </span>
                      </td>
                      <td className="py-2 text-ink font-medium">{r.name}</td>
                      <td className="py-2 text-right">{r.minutes}</td>
                      <td className="py-2 text-right">{r.readingDays}</td>
                      <td className="py-2 text-right">{r.books}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Card>

          {/* Needs support */}
          <Card>
            <SectionHeader icon="volunteer_activism" title="Students needing support" color="orange" />
            {report.needsSupport.length === 0 ? (
              <div className="flex items-center gap-2 text-sm text-lumi-green-dark">
                <Icon name="check_circle" size={18} />
                All students are actively engaged in reading.
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-muted border-b border-rule">
                    <th className="py-2 font-semibold">Student</th>
                    <th className="py-2 font-semibold text-right">Minutes</th>
                    <th className="py-2 font-semibold text-right">Days</th>
                    <th className="py-2 font-semibold text-right">Issue</th>
                  </tr>
                </thead>
                <tbody>
                  {report.needsSupport.map((r) => (
                    <tr key={r.id} className="border-b border-rule/60">
                      <td className="py-2 text-ink font-medium">{r.name}</td>
                      <td className="py-2 text-right">{r.minutes}</td>
                      <td className="py-2 text-right">{r.readingDays}</td>
                      <td className="py-2 text-right">
                        <Badge variant="warning">{r.issue}</Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </Card>

          {/* All students — the full roster, so no one is invisible in the report */}
          <Card>
            <SectionHeader icon="groups" title="All students" color="blue" />
            {report.students.length === 0 ? (
              <p className="text-sm text-muted">No students in this class.</p>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-muted border-b border-rule select-none">
                      <th className="py-2 font-semibold cursor-pointer" onClick={() => toggleSort('name')}>
                        Student{sortMark('name')}
                      </th>
                      <th className="py-2 font-semibold text-right cursor-pointer" onClick={() => toggleSort('minutes')}>
                        Minutes{sortMark('minutes')}
                      </th>
                      <th className="py-2 font-semibold text-right cursor-pointer" onClick={() => toggleSort('sessions')}>
                        Sessions{sortMark('sessions')}
                      </th>
                      <th className="py-2 font-semibold text-right cursor-pointer" onClick={() => toggleSort('readingDays')}>
                        Days{sortMark('readingDays')}
                      </th>
                      <th className="py-2 font-semibold text-right cursor-pointer" onClick={() => toggleSort('metPct')}>
                        Met target{sortMark('metPct')}
                      </th>
                      <th className="py-2 font-semibold text-right cursor-pointer" onClick={() => toggleSort('lastRead')}>
                        Last read{sortMark('lastRead')}
                      </th>
                      {levelsEnabled && <th className="py-2 font-semibold text-right">Level</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {sortedStudents.map((r) => (
                      <tr key={r.id} className="border-b border-rule/60 even:bg-cream/60">
                        <td className="py-2 text-ink font-medium">{r.name}</td>
                        <td className="py-2 text-right">{r.minutes}</td>
                        <td className="py-2 text-right">{r.sessions}</td>
                        <td className="py-2 text-right">{r.readingDays}</td>
                        <td className="py-2 text-right">{r.sessions > 0 ? `${r.metPct}%` : '—'}</td>
                        <td className="py-2 text-right">{r.lastRead ? formatDate(r.lastRead) : '—'}</td>
                        {levelsEnabled && (
                          <td className="py-2 text-right">{r.currentReadingLevel ?? '—'}</td>
                        )}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Card>

          {/* Reading level distribution — only when the school has reading levels enabled */}
          {levelsEnabled && (
          <Card>
            <SectionHeader icon="stacked_bar_chart" title="Reading levels" color="green" />
            {report.levelDistribution.length === 0 ? (
              <p className="text-sm text-muted">No students in this class.</p>
            ) : (
              <div className="space-y-2">
                {report.levelDistribution.map((l) => {
                  const pct = report.totalStudents > 0 ? Math.round((l.count / report.totalStudents) * 100) : 0;
                  return (
                    <div key={l.level} className="flex items-center gap-3">
                      <span className="text-sm text-ink w-28 shrink-0">{l.level}</span>
                      <div className="flex-1 h-2.5 rounded-full bg-cream overflow-hidden">
                        <div className="h-full bg-section" style={{ width: `${pct}%` }} />
                      </div>
                      <span className="text-xs text-muted w-10 text-right">{l.count}</span>
                    </div>
                  );
                })}
              </div>
            )}
            {report.popularLevel && (
              <p className="text-xs text-muted mt-3">
                Most common level: <span className="font-semibold text-ink">{report.popularLevel}</span>
                {report.longestStreak > 0 && <> · Longest streak: {report.longestStreak} days</>}
              </p>
            )}
          </Card>
          )}

          {report.totalStudents === 0 && (
            <EmptyState
              icon={<Icon name="assessment" size={40} />}
              title="No students in this class"
              description="Add students to the class to generate a report."
            />
          )}
        </div>
      )}

      {/* Print only the report region. `print-color-adjust: exact` forces the
          browser to keep the branded backgrounds/logo instead of stripping them. */}
      <style
        dangerouslySetInnerHTML={{
          __html:
            '@media print { body * { visibility: hidden !important; } #class-report, #class-report * { visibility: visible !important; -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; } #class-report { position: absolute; left: 0; top: 0; width: 100%; padding: 24px; } #class-report > * { break-inside: avoid; } }',
        }}
      />
    </div>
  );
}
