'use client';

import { useState } from 'react';
import {
  BarChart, Bar, LineChart, Line, PieChart, Pie, Cell,
  XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend,
} from 'recharts';
import { PageHeader } from '@/components/lumi/page-header';
import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { Tabs } from '@/components/lumi/tabs';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { Avatar } from '@/components/lumi/avatar';
import type {
  ReadingMetrics,
  EngagementPoint,
  LevelBucket,
  ClassComparisonRow,
  AtRiskStudent,
  TopReader,
  PopularBook,
} from '@/lib/firestore/analytics';

interface AnalyticsPageProps {
  metrics: ReadingMetrics;
  trend: EngagementPoint[];
  levels: LevelBucket[];
  classes: ClassComparisonRow[];
  atRisk: AtRiskStudent[];
  topReaders: TopReader[];
  books: PopularBook[];
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

export function AnalyticsPage({ metrics, trend, levels, classes, atRisk, topReaders, books }: AnalyticsPageProps) {
  const [activeTab, setActiveTab] = useState('overview');

  const tabs = [
    { id: 'overview', label: 'Overview', icon: <Icon name="bar_chart" size={18} /> },
    { id: 'classes', label: 'Classes', icon: <Icon name="school" size={18} />, count: classes.length },
    { id: 'students', label: 'Students', icon: <Icon name="person" size={18} /> },
    { id: 'books', label: 'Books', icon: <Icon name="library_books" size={18} />, count: books.length },
    { id: 'levels', label: 'Levels', icon: <Icon name="trending_up" size={18} /> },
  ];

  return (
    <div>
      <PageHeader title="Analytics" description="Last 30 days school-wide reading data" />

      {/* Top Metrics */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard
          title="Total Minutes"
          value={metrics.totalMinutes.toLocaleString()}
          icon={<Icon name="timer" />}
          color="pink"
        />
        <StatCard
          title="Books Read"
          value={metrics.totalBooks.toLocaleString()}
          icon={<Icon name="library_books" />}
          color="green"
        />
        <StatCard
          title="Completion Rate"
          value={`${metrics.completionRate}%`}
          icon={<Icon name="check_circle" />}
          color="blue"
        />
        <StatCard
          title="Avg Min/Student"
          value={metrics.avgMinPerStudent}
          icon={<Icon name="person" />}
          color="orange"
        />
      </div>

      <Tabs tabs={tabs} activeTab={activeTab} onChange={setActiveTab} />

      <div className="mt-4">
        {activeTab === 'overview' && <OverviewTab trend={trend} metrics={metrics} />}
        {activeTab === 'classes' && <ClassesTab classes={classes} />}
        {activeTab === 'students' && <StudentsTab atRisk={atRisk} topReaders={topReaders} />}
        {activeTab === 'books' && <BooksTab books={books} />}
        {activeTab === 'levels' && <LevelsTab levels={levels} />}
      </div>
    </div>
  );
}

// --- Overview Tab ---

function OverviewTab({ trend, metrics }: { trend: EngagementPoint[]; metrics: ReadingMetrics }) {
  // Aggregate to weekly if > 14 days
  const chartData = trend.length > 14
    ? aggregateWeekly(trend)
    : trend.map((p) => ({ label: formatShortDate(p.date), minutes: p.minutes, logs: p.logs }));

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Reading Minutes Trend</h3>
        {chartData.length === 0 ? (
          <EmptyState icon={<Icon name="bar_chart" size={40} />} title="No data" description="No reading logs in this period." />
        ) : (
          <div className="h-[280px]">
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
          <div className="h-[280px]">
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

      <Card className="lg:col-span-2">
        <h3 className="text-lg font-bold text-charcoal mb-2">Summary</h3>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          <div>
            <p className="text-sm text-text-secondary">Total Logs</p>
            <p className="text-xl font-bold text-charcoal">{metrics.totalLogs.toLocaleString()}</p>
          </div>
          <div>
            <p className="text-sm text-text-secondary">Unique Readers</p>
            <p className="text-xl font-bold text-charcoal">{metrics.uniqueReaders}</p>
          </div>
          <div>
            <p className="text-sm text-text-secondary">Completion Rate</p>
            <p className="text-xl font-bold text-charcoal">{metrics.completionRate}%</p>
          </div>
          <div>
            <p className="text-sm text-text-secondary">Avg Min/Student</p>
            <p className="text-xl font-bold text-charcoal">{metrics.avgMinPerStudent}</p>
          </div>
        </div>
      </Card>
    </div>
  );
}

// --- Classes Tab ---

function ClassesTab({ classes }: { classes: ClassComparisonRow[] }) {
  const columns: DataTableColumn<ClassComparisonRow>[] = [
    {
      id: 'name',
      header: 'Class',
      accessorFn: (r) => r.name,
      cell: (value, row) => (
        <div>
          <span className="font-semibold text-charcoal">{value as string}</span>
          {row.yearLevel && <span className="text-xs text-text-secondary ml-1">({row.yearLevel})</span>}
        </div>
      ),
      sortable: true,
    },
    { id: 'students', header: 'Students', accessorFn: (r) => r.studentCount, sortable: true },
    {
      id: 'minutes',
      header: 'Total Min',
      accessorFn: (r) => r.totalMinutes,
      cell: (v) => <span className="font-semibold">{(v as number).toLocaleString()}</span>,
      sortable: true,
    },
    {
      id: 'avg',
      header: 'Avg/Student',
      accessorFn: (r) => r.avgMinPerStudent,
      cell: (v) => `${v} min`,
      sortable: true,
    },
    { id: 'books', header: 'Books', accessorFn: (r) => r.booksRead, sortable: true },
    {
      id: 'completion',
      header: 'Completion',
      accessorFn: (r) => r.completionRate,
      cell: (v) => {
        const rate = v as number;
        const variant = rate >= 80 ? 'success' : rate >= 50 ? 'warning' : 'error';
        return <Badge variant={variant}>{rate}%</Badge>;
      },
      sortable: true,
    },
    {
      id: 'today',
      header: 'Today',
      accessorFn: (r) => r.readersToday,
      cell: (v, row) => (
        <span className="text-xs text-text-secondary">{v as number}/{row.studentCount}</span>
      ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={classes}
      emptyState={<EmptyState icon={<Icon name="school" size={40} />} title="No classes" description="No class data available." />}
    />
  );
}

// --- Students Tab ---

function StudentsTab({ atRisk, topReaders }: { atRisk: AtRiskStudent[]; topReaders: TopReader[] }) {
  const atRiskColumns: DataTableColumn<AtRiskStudent>[] = [
    {
      id: 'name',
      header: 'Student',
      accessorFn: (r) => r.name,
      cell: (v, row) => (
        <div className="flex items-center gap-2">
          <Avatar name={v as string} size="sm" />
          <div>
            <p className="font-semibold text-charcoal">{v as string}</p>
            <p className="text-xs text-text-secondary">{row.className}</p>
          </div>
        </div>
      ),
      sortable: true,
    },
    {
      id: 'level',
      header: 'Level',
      accessorFn: (r) => r.currentReadingLevel ?? '',
      cell: (v) => <ReadingLevelPill level={v as string || undefined} size="sm" />,
    },
    {
      id: 'days',
      header: 'Days Since Read',
      accessorFn: (r) => r.daysSinceRead,
      cell: (v) => {
        const d = v as number;
        const variant = d >= 14 ? 'error' : d >= 7 ? 'warning' : 'default';
        return <Badge variant={variant}>{d >= 999 ? 'Never' : `${d} days`}</Badge>;
      },
      sortable: true,
    },
    {
      id: 'lastRead',
      header: 'Last Read',
      accessorFn: (r) => r.lastReadingDate ?? '',
      cell: (v) => v ? new Date(v as string).toLocaleDateString() : 'Never',
    },
  ];

  const topColumns: DataTableColumn<TopReader>[] = [
    {
      id: 'name',
      header: 'Student',
      accessorFn: (r) => r.name,
      cell: (v, row) => (
        <div className="flex items-center gap-2">
          <Avatar name={v as string} size="sm" />
          <div>
            <p className="font-semibold text-charcoal">{v as string}</p>
            <p className="text-xs text-text-secondary">{row.className}</p>
          </div>
        </div>
      ),
    },
    {
      id: 'minutes',
      header: 'Total Min',
      accessorFn: (r) => r.totalMinutes,
      cell: (v) => <span className="font-bold text-charcoal">{(v as number).toLocaleString()}</span>,
      sortable: true,
    },
    {
      id: 'books',
      header: 'Books',
      accessorFn: (r) => r.totalBooks,
      sortable: true,
    },
    {
      id: 'streak',
      header: 'Streak',
      accessorFn: (r) => r.streak,
      cell: (v) => (v as number) > 0 ? <Badge variant="success">{v as number} days</Badge> : <span className="text-text-secondary">-</span>,
      sortable: true,
    },
  ];

  return (
    <div className="space-y-6">
      <Card>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-bold text-charcoal">At-Risk Students</h3>
          <Badge variant={atRisk.length > 0 ? 'error' : 'success'}>
            {atRisk.length} student{atRisk.length !== 1 ? 's' : ''}
          </Badge>
        </div>
        <p className="text-sm text-text-secondary mb-4">Students who haven&apos;t logged reading in 7+ days.</p>
        <DataTable
          columns={atRiskColumns}
          data={atRisk}
          pageSize={10}
          emptyState={<EmptyState icon={<Icon name="check_circle" size={40} />} title="All caught up" description="No at-risk students — everyone has read recently!" />}
        />
      </Card>

      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Top Readers</h3>
        <DataTable
          columns={topColumns}
          data={topReaders}
          emptyState={<EmptyState icon={<Icon name="emoji_events" size={40} />} title="No data" description="No reading stats available yet." />}
        />
      </Card>
    </div>
  );
}

// --- Books Tab ---

function BooksTab({ books }: { books: PopularBook[] }) {
  if (books.length === 0) {
    return <EmptyState icon={<Icon name="library_books" size={40} />} title="No books read" description="No books have been logged in the last 30 days." />;
  }

  const maxCount = Math.max(...books.map((b) => b.count), 1);

  return (
    <Card>
      <h3 className="text-lg font-bold text-charcoal mb-4">Most Read Books (Last 30 Days)</h3>
      <div className="h-[400px]">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={books} layout="vertical" margin={{ top: 5, right: 30, bottom: 5, left: 10 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="#E5E7EB" horizontal={false} />
            <XAxis type="number" tick={{ fill: '#6B7280', fontSize: 12 }} tickLine={false} axisLine={false} domain={[0, Math.ceil(maxCount * 1.1)]} allowDecimals={false} />
            <YAxis
              type="category"
              dataKey="title"
              tick={{ fill: '#374151', fontSize: 12, fontWeight: 500 }}
              tickLine={false}
              axisLine={false}
              width={180}
            />
            <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value: number) => [`${value} times`, 'Read']} />
            <Bar dataKey="count" fill="#5BB5E8" radius={[0, 4, 4, 0]} maxBarSize={24} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </Card>
  );
}

// --- Levels Tab ---

function LevelsTab({ levels }: { levels: LevelBucket[] }) {
  if (levels.length === 0) {
    return <EmptyState icon={<Icon name="trending_up" size={40} />} title="No level data" description="Students don't have reading levels assigned yet." />;
  }

  const total = levels.reduce((sum, l) => sum + l.count, 0);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Reading Level Distribution</h3>
        <div className="h-[320px]">
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie
                data={levels}
                dataKey="count"
                nameKey="level"
                cx="50%"
                cy="50%"
                innerRadius={60}
                outerRadius={120}
                paddingAngle={2}
                label={({ level, count }) => `${level} (${count})`}
                labelLine={false}
              >
                {levels.map((_, i) => (
                  <Cell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />
                ))}
              </Pie>
              <Tooltip contentStyle={TOOLTIP_STYLE} formatter={(value: number, name: string) => [`${value} students (${Math.round((value / total) * 100)}%)`, name]} />
            </PieChart>
          </ResponsiveContainer>
        </div>
      </Card>

      <Card>
        <h3 className="text-lg font-bold text-charcoal mb-4">Breakdown</h3>
        <div className="space-y-2 max-h-[340px] overflow-y-auto">
          {levels.map((bucket) => {
            const pct = total > 0 ? Math.round((bucket.count / total) * 100) : 0;
            return (
              <div key={bucket.level} className="flex items-center gap-3">
                <ReadingLevelPill level={bucket.level} size="sm" />
                <div className="flex-1">
                  <div className="h-2 bg-background rounded-full overflow-hidden">
                    <div
                      className="h-full bg-rose-pink rounded-full transition-all"
                      style={{ width: `${pct}%` }}
                    />
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
    </div>
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
