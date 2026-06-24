'use client';

import { useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { FilterChip } from '@/components/lumi/filter-chip';
import { EmptyState } from '@/components/lumi/empty-state';
import { useSchool } from '@/lib/hooks/use-school';
import { useClassReport } from '@/lib/hooks/use-reports';

function isoToday(): string {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

function isoDaysAgo(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() - days);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
}

function formatDate(iso: string): string {
  return new Date(`${iso}T00:00:00`).toLocaleDateString(undefined, {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

const PRESETS: { key: string; label: string; from: () => string }[] = [
  { key: '7', label: 'Last 7 days', from: () => isoDaysAgo(7) },
  { key: '30', label: 'Last 30 days', from: () => isoDaysAgo(30) },
  { key: '90', label: 'Last term (90 days)', from: () => isoDaysAgo(90) },
  { key: 'year', label: 'This year', from: () => `${new Date().getFullYear()}-01-01` },
];

interface ClassReportTabProps {
  classId: string;
  className: string;
  yearLevel?: string;
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded-[var(--radius-md)] border border-divider p-4">
      <p className="text-xs font-semibold text-text-secondary uppercase tracking-wide">{label}</p>
      <p className="text-2xl font-bold text-charcoal mt-1">{value}</p>
    </div>
  );
}

export function ClassReportTab({ classId, className, yearLevel }: ClassReportTabProps) {
  const { data: school } = useSchool();
  const [from, setFrom] = useState(isoDaysAgo(30));
  const [to, setTo] = useState(isoToday());
  const [presetKey, setPresetKey] = useState('30');

  const { data: report, isLoading } = useClassReport(classId, from, to);

  const applyPreset = (key: string) => {
    const preset = PRESETS.find((p) => p.key === key);
    if (!preset) return;
    setPresetKey(key);
    setFrom(preset.from());
    setTo(isoToday());
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
          <Button variant="outline" size="sm" onClick={() => window.print()} disabled={!report}>
            Print / Save as PDF
          </Button>
        </div>
        <div className="flex flex-wrap items-end gap-3">
          <label className="text-sm">
            <span className="block text-xs font-semibold text-text-secondary mb-1">From</span>
            <input
              type="date"
              value={from}
              max={to}
              onChange={(e) => {
                setFrom(e.target.value);
                setPresetKey('custom');
              }}
              className="px-3 py-2 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal text-sm focus:outline-none focus:ring-2 focus:ring-rose-pink/30"
            />
          </label>
          <label className="text-sm">
            <span className="block text-xs font-semibold text-text-secondary mb-1">To</span>
            <input
              type="date"
              value={to}
              min={from}
              max={isoToday()}
              onChange={(e) => {
                setTo(e.target.value);
                setPresetKey('custom');
              }}
              className="px-3 py-2 rounded-[var(--radius-md)] border border-divider bg-surface text-charcoal text-sm focus:outline-none focus:ring-2 focus:ring-rose-pink/30"
            />
          </label>
        </div>
      </div>

      {isLoading || !report ? (
        <p className="text-sm text-text-secondary py-10 text-center">Building report…</p>
      ) : (
        <div id="class-report" className="space-y-6">
          {/* Report header */}
          <div className="border-b border-divider pb-4">
            {school?.displayName || school?.name ? (
              <p className="text-sm text-text-secondary">{school.displayName || school.name}</p>
            ) : null}
            <h1 className="text-2xl font-bold text-charcoal">Class Reading Report</h1>
            <p className="text-sm text-text-secondary mt-0.5">
              {[className, yearLevel].filter(Boolean).join(' · ')} · {formatDate(from)} – {formatDate(to)}
            </p>
          </div>

          {/* Headline metrics */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <Metric label="Students" value={report.totalStudents} />
            <Metric label="Active readers" value={report.activeReaders} />
            <Metric label="Engagement" value={`${report.engagementRate}%`} />
            <Metric label="Met target" value={`${report.targetMetRate}%`} />
            <Metric label="Total minutes" value={report.totalMinutes} />
            <Metric label="Avg min / student" value={report.avgMinutesPerStudent} />
            <Metric label="Books read" value={report.totalBooks} />
            <Metric label="Sessions" value={report.totalSessions} />
          </div>

          {/* Top readers */}
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-3">Top readers</h2>
            {report.topReaders.length === 0 ? (
              <p className="text-sm text-text-secondary">No reading recorded in this period.</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-text-secondary border-b border-divider">
                    <th className="py-2 font-semibold w-8">#</th>
                    <th className="py-2 font-semibold">Student</th>
                    <th className="py-2 font-semibold text-right">Minutes</th>
                    <th className="py-2 font-semibold text-right">Days</th>
                    <th className="py-2 font-semibold text-right">Books</th>
                  </tr>
                </thead>
                <tbody>
                  {report.topReaders.map((r, i) => (
                    <tr key={r.id} className="border-b border-divider/60">
                      <td className="py-2 text-text-secondary">{i + 1}</td>
                      <td className="py-2 text-charcoal font-medium">{r.name}</td>
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
            <h2 className="text-lg font-bold text-charcoal mb-3">Students needing support</h2>
            {report.needsSupport.length === 0 ? (
              <div className="flex items-center gap-2 text-sm text-mint-green-dark">
                <Icon name="check_circle" size={18} />
                All students are actively engaged in reading.
              </div>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-text-secondary border-b border-divider">
                    <th className="py-2 font-semibold">Student</th>
                    <th className="py-2 font-semibold text-right">Minutes</th>
                    <th className="py-2 font-semibold text-right">Days</th>
                    <th className="py-2 font-semibold text-right">Issue</th>
                  </tr>
                </thead>
                <tbody>
                  {report.needsSupport.map((r) => (
                    <tr key={r.id} className="border-b border-divider/60">
                      <td className="py-2 text-charcoal font-medium">{r.name}</td>
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

          {/* Reading level distribution */}
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-3">Reading levels</h2>
            {report.levelDistribution.length === 0 ? (
              <p className="text-sm text-text-secondary">No students in this class.</p>
            ) : (
              <div className="space-y-2">
                {report.levelDistribution.map((l) => {
                  const pct = report.totalStudents > 0 ? Math.round((l.count / report.totalStudents) * 100) : 0;
                  return (
                    <div key={l.level} className="flex items-center gap-3">
                      <span className="text-sm text-charcoal w-28 shrink-0">{l.level}</span>
                      <div className="flex-1 h-2.5 rounded-full bg-background overflow-hidden">
                        <div className="h-full bg-rose-pink" style={{ width: `${pct}%` }} />
                      </div>
                      <span className="text-xs text-text-secondary w-10 text-right">{l.count}</span>
                    </div>
                  );
                })}
              </div>
            )}
            {report.popularLevel && (
              <p className="text-xs text-text-secondary mt-3">
                Most common level: <span className="font-semibold text-charcoal">{report.popularLevel}</span>
                {report.longestStreak > 0 && <> · Longest streak: {report.longestStreak} days</>}
              </p>
            )}
          </Card>

          {report.totalStudents === 0 && (
            <EmptyState
              icon={<Icon name="assessment" size={40} />}
              title="No students in this class"
              description="Add students to the class to generate a report."
            />
          )}
        </div>
      )}

      {/* Print only the report region. */}
      <style
        dangerouslySetInnerHTML={{
          __html:
            '@media print { body * { visibility: hidden !important; } #class-report, #class-report * { visibility: visible !important; } #class-report { position: absolute; left: 0; top: 0; width: 100%; padding: 24px; } }',
        }}
      />
    </div>
  );
}
