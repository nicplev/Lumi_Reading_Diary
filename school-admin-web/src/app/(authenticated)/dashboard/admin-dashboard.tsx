'use client';

import { useState } from 'react';
import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';
import { formatRelativeTime } from '@/lib/utils/formatters';
import { sectionForPath } from '@/lib/theme/sections';
import { WeeklyClassChart } from './weekly-class-chart';
import Link from 'next/link';
import type { DashboardStats, WeeklyEngagement, WeeklyClassSeries } from '@/lib/firestore/dashboard';

interface AdminDashboardProps {
  schoolName: string;
  stats: DashboardStats;
  weeklyEngagement: WeeklyEngagement[];
  classSeries: WeeklyClassSeries;
  recentActivity: Array<{
    id: string;
    studentName: string;
    action: string;
    time: string;
    bookTitle?: string;
  }>;
}

// Each shortcut is tinted by the colour of the section it jumps to, so the
// palette doubles as wayfinding rather than decoration.
const shortcuts = [
  { label: 'Add Staff',    href: '/users',        icon: <Icon name="person_add" size={20} /> },
  { label: 'Add Class',    href: '/classes',      icon: <Icon name="school" size={20} /> },
  { label: 'Reports',      href: '/analytics',    icon: <Icon name="bar_chart" size={20} /> },
  { label: 'Parents/Guardians', href: '/parent-links', icon: <Icon name="link" size={20} /> },
];

export function AdminDashboard({ schoolName, stats, weeklyEngagement, classSeries, recentActivity }: AdminDashboardProps) {
  const [metric, setMetric] = useState<'logs' | 'minutes'>('logs');
  const avg7 = weeklyEngagement.length
    ? weeklyEngagement.reduce((s, d) => s + d.count, 0) / weeklyEngagement.length
    : 0;
  const activeDeltaPct = avg7 > 0
    ? Math.round(((stats.activeStudentsToday - avg7) / avg7) * 100)
    : null;
  const activeSubtitle = activeDeltaPct === null
    ? 'no activity yet'
    : activeDeltaPct === 0
      ? 'on par with 7-day avg'
      : `${activeDeltaPct > 0 ? '↑' : '↓'} ${Math.abs(activeDeltaPct)}% vs 7-day avg`;

  const weekTotal = weeklyEngagement.reduce((s, d) => s + d.count, 0);
  const weekMinutes = weeklyEngagement.reduce((s, d) => s + (d.minutes ?? 0), 0);
  const weekRangeLabel = weeklyEngagement.length
    ? `${weeklyEngagement[0].day} – ${weeklyEngagement[weeklyEngagement.length - 1].day}`
    : '';

  return (
    <div>
      <PageHeader
        eyebrow="Dashboard"
        title={schoolName}
        description="School administration dashboard"
        action={
          <Link href="/analytics">
            <Button variant="outline" size="sm">
              <Icon name="insights" size={18} />
              <span className="ml-2">View Analytics</span>
            </Button>
          </Link>
        }
      />

      {/* Stats Grid — section-blue throughout; icons + labels do the distinguishing */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard title="Students"     value={stats.totalStudents}        icon={<Icon name="person" />}       color="blue" href="/students"  subtitle="enrolled" />
        <StatCard title="Teachers"     value={stats.totalTeachers}        icon={<Icon name="badge" />}        color="blue" href="/users"     subtitle="on staff" />
        <StatCard title="Classes"      value={stats.totalClasses}         icon={<Icon name="school" />}       color="blue" href="/classes"   subtitle="active" />
        <StatCard title="Active Today" value={stats.activeStudentsToday}  icon={<Icon name="auto_stories" />} color="blue" href="/analytics" subtitle={activeSubtitle} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Weekly Engagement Chart */}
        <div className="lg:col-span-2">
          <Card className="h-full flex flex-col">
            <div className="flex items-start justify-between mb-4 gap-3">
              <div>
                <h2 className="text-lg font-bold text-ink">Weekly Reading Activity</h2>
                {weekRangeLabel && (
                  <p className="text-xs text-muted mt-0.5">{weekRangeLabel}</p>
                )}
              </div>
              <div className="flex flex-col items-end gap-2">
                {/* Toggle: glance at the same week as logs or minutes read */}
                <div className="inline-flex rounded-full border border-rule bg-cream p-0.5 text-xs font-semibold">
                  {(['logs', 'minutes'] as const).map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => setMetric(m)}
                      className={`px-2.5 py-1 rounded-full capitalize transition ${
                        metric === m ? 'bg-paper text-ink shadow-card' : 'text-muted hover:text-ink'
                      }`}
                    >
                      {m}
                    </button>
                  ))}
                </div>
                <div className="text-right">
                  <div className="font-display text-[22px] font-extrabold text-ink leading-tight">
                    {metric === 'minutes' ? weekMinutes : weekTotal}
                  </div>
                  <div className="text-xs text-muted">
                    {metric === 'minutes' ? 'min this week' : 'logs this week'}
                  </div>
                </div>
              </div>
            </div>
            <div className="flex-1 min-h-0">
              {classSeries.classes.length > 0 ? (
                <WeeklyClassChart classes={classSeries.classes} rows={classSeries.rows} metric={metric} />
              ) : (
                <div className="flex h-full min-h-[220px] items-center justify-center text-center">
                  <p className="text-sm text-muted">No reading logged yet this week.</p>
                </div>
              )}
            </div>
          </Card>
        </div>

        {/* Right column: Shortcuts + Recent Activity — matching Card containers */}
        <div className="flex flex-col gap-6 min-w-0">
          <Card>
            <h2 className="text-lg font-bold text-ink mb-3">Shortcuts</h2>
            <div className="grid grid-cols-2 gap-2">
              {shortcuts.map((action) => {
                const accent = sectionForPath(action.href).accent;
                return (
                  <Link
                    key={action.href}
                    href={action.href}
                    className="flex items-center gap-2.5 p-2.5 rounded-[var(--radius-md)] bg-cream hover:brightness-[0.97] transition"
                  >
                    <span
                      className="inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-md)] flex-shrink-0"
                      style={{ backgroundColor: `${accent}1F`, color: accent }}
                    >
                      {action.icon}
                    </span>
                    <span className="text-sm font-semibold text-ink truncate">{action.label}</span>
                  </Link>
                );
              })}
            </div>
          </Card>

          <Card className="flex-1 flex flex-col min-h-0">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-ink">Recent Activity</h2>
              {recentActivity.length > 0 && (
                <Link href="/analytics" className="text-xs font-semibold text-section hover:underline">
                  View all
                </Link>
              )}
            </div>
            {recentActivity.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-6">
                <span className="text-muted/40 mb-2"><Icon name="history" size={28} /></span>
                <p className="text-sm font-semibold text-ink">Nothing yet today</p>
                <p className="text-xs text-muted mt-0.5">Activity appears here as students log books.</p>
              </div>
            ) : (
              <ul className="space-y-3 overflow-y-auto flex-1 -mr-2 pr-2">
                {recentActivity.map((activity) => (
                  <li key={activity.id} className="flex items-start gap-3">
                    <div className="w-9 h-9 rounded-full bg-tint-blue flex items-center justify-center flex-shrink-0 text-lumi-blue-dark">
                      <Icon name="menu_book" size={18} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-ink truncate">{activity.studentName}</p>
                      <p className="text-xs text-muted truncate">
                        {activity.action}{activity.bookTitle ? ` · ${activity.bookTitle}` : ''}
                      </p>
                    </div>
                    <span className="text-xs text-muted flex-shrink-0 whitespace-nowrap">{formatRelativeTime(activity.time)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
