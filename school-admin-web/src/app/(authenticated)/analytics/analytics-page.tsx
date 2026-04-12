'use client';

import { useState, useRef, useEffect } from 'react';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import { PageHeader } from '@/components/lumi/page-header';
import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { Avatar } from '@/components/lumi/avatar';
import { useAnalytics, type AnalyticsPeriod } from '@/lib/hooks/use-analytics';
import type {
  EngagementPoint,
  LevelBucket,
  ClassComparisonRow,
  AtRiskStudent,
  TopReader,
  PopularBook,
} from '@/lib/firestore/analytics';

interface AnalyticsPageProps {
  levelSchema: string;
  termDates: Record<string, string>; // ISO strings
}

const PIE_COLORS = [
  '#FF8698', '#6DD4A1', '#FFD166', '#5BB5E8', '#C490D1',
  '#FF6B8A', '#45C49B', '#FFB84D', '#4A9FD9', '#B77BC4',
  '#E8E8E8',
];

const TOOLTIP_STYLE = {
  backgroundColor: '#FFFFFF',
  border: '1px solid #E5E7EB',
  borderRadius: '12px',
  fontSize: '13px',
  fontWeight: 600,
  boxShadow: '0 4px 10px -6px rgba(18,18,17,0.1)',
};

function detectCurrentTerm(termDates: Record<string, string>): string {
  const now = new Date();
  for (let i = 1; i <= 4; i++) {
    const start = termDates[`term${i}Start`] ? new Date(termDates[`term${i}Start`]) : null;
    const end = termDates[`term${i}End`] ? new Date(termDates[`term${i}End`]) : null;
    if (start && end && now >= start && now <= end) return `term${i}`;
  }
  // Fall back to most recent past term
  let latestTerm = 'term1';
  let latestEnd: Date | null = null;
  for (let i = 1; i <= 4; i++) {
    const start = termDates[`term${i}Start`] ? new Date(termDates[`term${i}Start`]) : null;
    const end = termDates[`term${i}End`] ? new Date(termDates[`term${i}End`]) : null;
    if (start && end && end < now && (!latestEnd || end > latestEnd)) {
      latestEnd = end;
      latestTerm = `term${i}`;
    }
  }
  return latestTerm;
}

function formatDate(d: Date): string {
  return d.toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: '2-digit' });
}

function formatSubtitle(period: AnalyticsPeriod, termKey: string, termDates: Record<string, string>): string {
  if (period === '5days') return 'Last 5 school days';
  if (period === 'month') {
    const now = new Date();
    return `${now.toLocaleString('default', { month: 'long' })} (school days)`;
  }
  if (period === 'term') {
    const termNum = termKey.replace('term', '');
    const start = termDates[`${termKey}Start`] ? new Date(termDates[`${termKey}Start`]) : null;
    const end = termDates[`${termKey}End`] ? new Date(termDates[`${termKey}End`]) : null;
    if (start && end) return `Term ${termNum}: ${formatDate(start)} – ${formatDate(end)}`;
    return `Term ${termNum}`;
  }
  // year
  const termStarts = [1, 2, 3, 4]
    .map((i) => termDates[`term${i}Start`])
    .filter(Boolean)
    .map((d) => new Date(d))
    .sort((a, b) => a.getTime() - b.getTime());
  const termEnds = [1, 2, 3, 4]
    .map((i) => termDates[`term${i}End`])
    .filter(Boolean)
    .map((d) => new Date(d))
    .sort((a, b) => b.getTime() - a.getTime());
  if (termStarts.length && termEnds.length) {
    return `School year: ${formatDate(termStarts[0])} – ${formatDate(termEnds[0])}`;
  }
  return 'Full school year';
}

export function AnalyticsPage({ levelSchema, termDates }: AnalyticsPageProps) {
  const [period, setPeriod] = useState<AnalyticsPeriod>('month');
  const [termKey, setTermKey] = useState<string>(() => detectCurrentTerm(termDates));
  const [termDropdownOpen, setTermDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const { data, isFetching } = useAnalytics(period, period === 'term' ? termKey : undefined);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setTermDropdownOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  const configuredTerms = [1, 2, 3, 4].filter((i) => termDates[`term${i}Start`]);

  const metrics = data?.metrics;
  const trend = data?.trend ?? [];
  const levels = data?.levels ?? [];
  const classes = data?.classes ?? [];
  const atRisk = data?.atRisk ?? [];
  const topReaders = data?.topReaders ?? [];
  const books = data?.books ?? [];

  const chartData = trend.length > 14
    ? aggregateWeekly(trend)
    : trend.map((p) => ({ label: formatShortDate(p.date), minutes: p.minutes, logs: p.logs }));

  const totalStudents = classes.reduce((sum, c) => sum + c.studentCount, 0);
  const activeThisWeek = Math.max(totalStudents - atRisk.length, 0);
  const participationPct = totalStudents > 0 ? Math.round((activeThisWeek / totalStudents) * 100) : 0;

  const subtitle = formatSubtitle(period, termKey, termDates);

  return (
    <div>
      <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4 mb-6">
        <PageHeader title="Analytics" description={subtitle} />

        {/* Period toggle */}
        <div className="flex items-center gap-1.5 flex-wrap shrink-0">
          {(['5days', 'month', 'year'] as const).map((p) => (
            <button
              key={p}
              onClick={() => setPeriod(p)}
              className={`px-3 py-1.5 rounded-full text-xs font-semibold transition-all ${
                period === p
                  ? 'bg-rose-pink text-white shadow-sm'
                  : 'bg-background text-text-secondary hover:text-charcoal border border-gray-200'
              }`}
            >
              {p === '5days' ? 'Last 5 Days' : p === 'month' ? 'This Month' : 'School Year'}
            </button>
          ))}

          {configuredTerms.length > 0 && (
            <div ref={dropdownRef} className="relative">
              <button
                onClick={() => { setPeriod('term'); setTermDropdownOpen((o) => !o); }}
                className={`px-3 py-1.5 rounded-full text-xs font-semibold transition-all flex items-center gap-1 ${
                  period === 'term'
                    ? 'bg-rose-pink text-white shadow-sm'
                    : 'bg-background text-text-secondary hover:text-charcoal border border-gray-200'
                }`}
              >
                {period === 'term' ? `Term ${termKey.replace('term', '')}` : 'School Term'}
                <Icon name="expand_more" size={14} />
              </button>
              {termDropdownOpen && (
                <div className="absolute right-0 top-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg z-20 py-1 min-w-[100px]">
                  {configuredTerms.map((i) => (
                    <button
                      key={i}
                      onClick={() => { setTermKey(`term${i}`); setPeriod('term'); setTermDropdownOpen(false); }}
                      className={`w-full text-left px-3 py-2 text-xs font-semibold hover:bg-background transition-colors flex items-center justify-between gap-2 ${
                        termKey === `term${i}` ? 'text-rose-pink' : 'text-charcoal'
                      }`}
                    >
                      Term {i}
                      {termKey === `term${i}` && period === 'term' && <Icon name="check" size={14} />}
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {isFetching && (
            <div className="w-4 h-4 rounded-full border-2 border-rose-pink border-t-transparent animate-spin" />
          )}
        </div>
      </div>

      <div className={`transition-opacity duration-200 ${isFetching ? 'opacity-50 pointer-events-none' : 'opacity-100'}`}>
        {/* Top Metrics */}
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <StatCard
            title="Total Minutes"
            value={metrics ? metrics.totalMinutes.toLocaleString() : '—'}
            icon={<Icon name="timer" />}
            color="pink"
            subtitle="school-wide this period"
          />
          <StatCard
            title="Participation"
            value={`${participationPct}%`}
            icon={<Icon name="groups" />}
            color="green"
            subtitle={`${activeThisWeek} of ${totalStudents} students active`}
          />
          <StatCard
            title="Avg Min / Student"
            value={metrics ? `${metrics.avgMinPerStudent}` : '—'}
            icon={<Icon name="trending_up" />}
            color="blue"
            subtitle="across all students this period"
          />
          <StatCard
            title="Students Inactive"
            value={atRisk.length}
            icon={<Icon name="warning" />}
            color="orange"
            subtitle="haven't read in 7+ days"
          />
        </div>

        {/* Main grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Row 1: Trend charts */}
          <Card>
            <h3 className="text-lg font-bold text-charcoal mb-4">Reading Minutes Trend</h3>
            {chartData.length === 0 ? (
              <EmptyState icon={<Icon name="bar_chart" size={40} />} title="No data" description="No reading logs in this period." />
            ) : (
              <div className="h-[240px]">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart data={chartData} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                    <XAxis dataKey="label" tick={{ fill: '#6B7280', fontSize: 11, fontWeight: 600 }} tickLine={false} axisLine={{ stroke: '#E5E7EB' }} />
                    <YAxis tick={{ fill: '#6B7280', fontSize: 12 }} tickLine={false} axisLine={false} allowDecimals={false} />
                    <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value: number) => [`${value} min`, 'Minutes']} />
                    <Line type="monotone" dataKey="minutes" stroke="#FF8698" strokeWidth={2.5} dot={false} activeDot={{ r: 5, fill: '#FF8698' }} />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}
          </Card>

          <Card>
            <h3 className="text-lg font-bold text-charcoal mb-4">Daily Logs Trend</h3>
            {chartData.length === 0 ? (
              <EmptyState icon={<Icon name="bar_chart" size={40} />} title="No data" description="No reading logs in this period." />
            ) : (
              <div className="h-[240px]">
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={chartData} margin={{ top: 5, right: 5, bottom: 5, left: -15 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" vertical={false} />
                    <XAxis dataKey="label" tick={{ fill: '#6B7280', fontSize: 11, fontWeight: 600 }} tickLine={false} axisLine={{ stroke: '#E5E7EB' }} />
                    <YAxis tick={{ fill: '#6B7280', fontSize: 12 }} tickLine={false} axisLine={false} allowDecimals={false} />
                    <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value: number) => [`${value} logs`, 'Logs']} />
                    <Bar dataKey="logs" fill="#6DD4A1" radius={[4, 4, 0, 0]} maxBarSize={32} />
                  </BarChart>
                </ResponsiveContainer>
              </div>
            )}
          </Card>

          {/* Row 2: At-risk + Class performance */}
          <AtRiskSpotlightCard atRisk={atRisk} />
          <ClassSnapshotCard classes={classes} />

          {/* Row 3: Top readers + Top books */}
          <TopReadersCard topReaders={topReaders} />
          <TopBooksCard books={books} />

          {/* Levels — full width, only when schema is set */}
          {levelSchema !== 'none' && levels.length > 0 && (
            <LevelsSection levels={levels} />
          )}
        </div>
      </div>
    </div>
  );
}

// --- Needs Attention ---

function AtRiskSpotlightCard({ atRisk }: { atRisk: AtRiskStudent[] }) {
  const [expanded, setExpanded] = useState(false);
  const COLLAPSED_LIMIT = 4;
  const capped = atRisk.slice(0, 20);
  const visible = expanded ? capped : capped.slice(0, COLLAPSED_LIMIT);
  const canExpand = capped.length > COLLAPSED_LIMIT;

  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-bold text-charcoal">Needs Attention</h3>
        <Badge variant={atRisk.length > 0 ? 'error' : 'success'}>
          {atRisk.length} student{atRisk.length !== 1 ? 's' : ''}
        </Badge>
      </div>

      {atRisk.length === 0 ? (
        <div className="flex items-center gap-3 py-4 text-text-secondary">
          <Icon name="check_circle" size={24} className="text-green-500" />
          <div>
            <p className="font-semibold text-charcoal text-sm">Everyone&apos;s reading on track</p>
            <p className="text-xs">No students have been inactive this period.</p>
          </div>
        </div>
      ) : (
        <>
          <div className={`space-y-3 ${expanded ? 'max-h-[360px] overflow-y-auto pr-1' : ''}`}>
            {visible.map((student) => {
              const variant = student.daysSinceRead >= 14 ? 'error' : 'warning';
              const label = student.daysSinceRead >= 999 ? 'Never' : `${student.daysSinceRead}d ago`;
              return (
                <div key={student.id} className="flex items-center gap-3">
                  <Avatar name={student.name} size="sm" />
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-charcoal text-sm truncate">{student.name}</p>
                    <p className="text-xs text-text-secondary truncate">{student.className}</p>
                  </div>
                  <Badge variant={variant}>{label}</Badge>
                </div>
              );
            })}
          </div>
          {canExpand && (
            <button
              onClick={() => setExpanded((e) => !e)}
              className="mt-3 text-xs font-semibold text-text-secondary hover:text-charcoal transition-colors flex items-center gap-1"
            >
              <Icon name={expanded ? 'expand_less' : 'expand_more'} size={16} />
              {expanded ? 'Show less' : `Show all ${capped.length} students`}
            </button>
          )}
        </>
      )}
    </Card>
  );
}

// --- Class Performance ---

function ClassSnapshotCard({ classes }: { classes: ClassComparisonRow[] }) {
  const withMetrics = classes.map((cls) => ({
    ...cls,
    sessionsPerStudent: cls.studentCount > 0 ? cls.totalLogs / cls.studentCount : 0,
    booksPerStudent: cls.studentCount > 0 ? cls.booksRead / cls.studentCount : 0,
  }));
  const maxSPS = Math.max(...withMetrics.map((c) => c.sessionsPerStudent), 1);
  const maxBPS = Math.max(...withMetrics.map((c) => c.booksPerStudent), 1);
  const ranked = withMetrics
    .map((cls) => ({
      ...cls,
      score: ((cls.sessionsPerStudent / maxSPS) + (cls.booksPerStudent / maxBPS)) / 2 * 100,
    }))
    .sort((a, b) => b.score - a.score);

  const maxLogs = Math.max(...classes.map((c) => c.totalLogs), 1);
  const maxBooks = Math.max(...classes.map((c) => c.booksRead), 1);

  return (
    <Card>
      <div className="flex items-center justify-between mb-5">
        <h3 className="text-lg font-bold text-charcoal">Class Performance</h3>
        <div className="flex items-center gap-3">
          <span className="flex items-center gap-1.5 text-xs text-text-secondary">
            <span className="inline-block w-3 h-2 rounded-sm bg-[#FF8698]" />
            Sessions
          </span>
          <span className="flex items-center gap-1.5 text-xs text-text-secondary">
            <span className="inline-block w-3 h-2 rounded-sm bg-[#6DD4A1]" />
            Books
          </span>
        </div>
      </div>

      {ranked.length === 0 ? (
        <EmptyState icon={<Icon name="school" size={40} />} title="No classes" description="No class data available." />
      ) : (
        <div className="space-y-5">
          {ranked.map((cls, i) => (
            <div key={cls.classId}>
              <div className="flex items-center gap-2 mb-2">
                <span className="text-xs font-bold text-text-secondary w-5 shrink-0">#{i + 1}</span>
                <span className="text-sm font-semibold text-charcoal">
                  {cls.name}
                  {cls.yearLevel && <span className="text-xs text-text-secondary font-normal ml-1">({cls.yearLevel})</span>}
                </span>
              </div>
              <div className="space-y-1.5 pl-7">
                <div className="flex items-center gap-2">
                  <div className="flex-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                    <div className="h-full bg-[#FF8698] rounded-full transition-all" style={{ width: `${Math.min((cls.totalLogs / maxLogs) * 100, 100)}%` }} />
                  </div>
                  <span className="text-xs text-text-secondary w-20 text-right shrink-0">{cls.totalLogs} sessions</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex-1 h-2 bg-gray-100 rounded-full overflow-hidden">
                    <div className="h-full bg-[#6DD4A1] rounded-full transition-all" style={{ width: `${Math.min((cls.booksRead / maxBooks) * 100, 100)}%` }} />
                  </div>
                  <span className="text-xs text-text-secondary w-20 text-right shrink-0">{cls.booksRead} book{cls.booksRead !== 1 ? 's' : ''}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// --- Top Readers (condensed) ---

function TopReadersCard({ topReaders }: { topReaders: TopReader[] }) {
  const top5 = topReaders.slice(0, 5);
  const maxMinutes = Math.max(...top5.map((r) => r.totalMinutes), 1);

  return (
    <Card>
      <h3 className="text-lg font-bold text-charcoal mb-4">Top Readers</h3>
      {top5.length === 0 ? (
        <EmptyState icon={<Icon name="emoji_events" size={40} />} title="No data" description="No reading stats available yet." />
      ) : (
        <div className="space-y-4">
          {top5.map((reader, i) => (
            <div key={reader.id} className="flex items-center gap-3">
              <span className="text-xs font-bold text-text-secondary w-5 shrink-0">#{i + 1}</span>
              <Avatar name={reader.name} size="sm" />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-charcoal truncate">{reader.name}</p>
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-[#FF8698] rounded-full transition-all"
                      style={{ width: `${Math.min((reader.totalMinutes / maxMinutes) * 100, 100)}%` }}
                    />
                  </div>
                </div>
              </div>
              <div className="text-right shrink-0">
                <p className="text-sm font-bold text-charcoal">{reader.totalMinutes.toLocaleString()} min</p>
                {reader.uniqueBooks > 0 && (
                  <p className="text-xs text-text-secondary">{reader.uniqueBooks} book{reader.uniqueBooks !== 1 ? 's' : ''}</p>
                )}
              </div>
              {reader.streak > 0 && (
                <span title="Current reading streak">
                  <Badge variant="success">
                    <Icon name="local_fire_department" size={14} className="text-warm-orange mr-0.5 leading-none -mt-[3px]" />
                    {reader.streak}d
                  </Badge>
                </span>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// --- Top Books (condensed) ---

function TopBooksCard({ books }: { books: PopularBook[] }) {
  const top5 = books.slice(0, 5);
  const maxCount = Math.max(...top5.map((b) => b.count), 1);

  return (
    <Card>
      <h3 className="text-lg font-bold text-charcoal mb-4">Most Read Books</h3>
      {top5.length === 0 ? (
        <EmptyState icon={<Icon name="library_books" size={40} />} title="No books" description="No books have been logged in this period." />
      ) : (
        <div className="space-y-4">
          {top5.map((book, i) => (
            <div key={book.title} className="flex items-center gap-3">
              <span className="text-xs font-bold text-text-secondary w-5 shrink-0">#{i + 1}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold text-charcoal truncate">{book.title}</p>
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 h-1.5 bg-gray-100 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-[#5BB5E8] rounded-full transition-all"
                      style={{ width: `${Math.min((book.count / maxCount) * 100, 100)}%` }}
                    />
                  </div>
                </div>
              </div>
              <span className="text-sm font-bold text-charcoal shrink-0">
                {book.count}×
              </span>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// --- Levels (full width, conditional) ---

function LevelsSection({ levels }: { levels: LevelBucket[] }) {
  const total = levels.reduce((sum, l) => sum + l.count, 0);

  return (
    <>
      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Reading Level Distribution</h3>
        <div className="h-[280px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={levels}
                dataKey="count"
                nameKey="level"
                cx="50%"
                cy="50%"
                innerRadius={55}
                outerRadius={100}
                paddingAngle={2}
                label={({ name, value }) => `${name} (${value})`}
              >
                {levels.map((_, i) => (
                  <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value: number, name: string) => [`${value} students (${Math.round((value / total) * 100)}%)`, name]} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </Card>

      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Level Breakdown</h3>
        <div className="space-y-2 max-h-[300px] overflow-y-auto">
          {levels.map((bucket) => {
            const pct = total > 0 ? Math.round((bucket.count / total) * 100) : 0;
            return (
              <div key={bucket.level} className="flex items-center gap-3">
                <ReadingLevelPill level={bucket.level} size="sm" />
                <div className="flex-1">
                  <div className="h-2 bg-background rounded-full overflow-hidden">
                    <div className="h-full bg-rose-pink rounded-full transition-all" style={{ width: `${pct}%` }} />
                  </div>
                </div>
                <span className="text-sm font-semibold text-charcoal w-16 text-right">
                  {bucket.count} <span className="text-text-secondary font-normal text-xs">({pct}%)</span>
                </span>
              </div>
            );
          })}
        </div>
      </Card>
    </>
  );
}

// --- Utilities ---

function formatShortDate(dateStr: string): string {
  const d = new Date(dateStr);
  return `${d.getDate()}/${d.getMonth() + 1}`;
}

function aggregateWeekly(points: EngagementPoint[]): { label: string; minutes: number; logs: number }[] {
  const weeks: { label: string; minutes: number; logs: number }[] = [];
  for (let i = 0; i < points.length; i += 7) {
    const chunk = points.slice(i, i + 7);
    const minutes = chunk.reduce((s, p) => s + p.minutes, 0);
    const logs = chunk.reduce((s, p) => s + p.logs, 0);
    const startDate = formatShortDate(chunk[0].date);
    const endDate = formatShortDate(chunk[chunk.length - 1].date);
    weeks.push({ label: `${startDate}-${endDate}`, minutes, logs });
  }
  return weeks;
}
