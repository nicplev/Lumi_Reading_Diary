'use client';

import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Icon } from '@/components/lumi/icon';
import { formatRelativeTime } from '@/lib/utils/formatters';
import { WeeklyChart } from './weekly-chart';
import Link from 'next/link';
import type { DashboardStats, WeeklyEngagement } from '@/lib/firestore/dashboard';

interface AdminDashboardProps {
  schoolName: string;
  stats: DashboardStats;
  weeklyEngagement: WeeklyEngagement[];
  recentActivity: Array<{
    id: string;
    studentName: string;
    action: string;
    time: string;
    bookTitle?: string;
  }>;
}

const shortcuts = [
  { label: 'Add User',     href: '/users',        icon: <Icon name="person_add" size={20} />, colorClass: 'bg-rose-pink/10 text-rose-pink' },
  { label: 'Add Class',    href: '/classes',      icon: <Icon name="school" size={20} />,     colorClass: 'bg-mint-green/40 text-mint-green-dark' },
  { label: 'Reports',      href: '/analytics',    icon: <Icon name="bar_chart" size={20} />,  colorClass: 'bg-warm-orange/10 text-warm-orange' },
  { label: 'Parent Links', href: '/parent-links', icon: <Icon name="link" size={20} />,       colorClass: 'bg-sky-blue/40 text-sky-blue-dark' },
];

export function AdminDashboard({ schoolName, stats, weeklyEngagement, recentActivity }: AdminDashboardProps) {
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
  const weekRangeLabel = weeklyEngagement.length
    ? `${weeklyEngagement[0].day} – ${weeklyEngagement[weeklyEngagement.length - 1].day}`
    : '';

  return (
    <div>
      <PageHeader
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

      {/* Stats Grid — every card identical structure */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard title="Students"     value={stats.totalStudents}        icon={<Icon name="person" />}       color="pink"   href="/students"  subtitle="enrolled" />
        <StatCard title="Teachers"     value={stats.totalTeachers}        icon={<Icon name="badge" />}        color="blue"   href="/users"     subtitle="on staff" />
        <StatCard title="Classes"      value={stats.totalClasses}         icon={<Icon name="school" />}       color="green"  href="/classes"   subtitle="active" />
        <StatCard title="Active Today" value={stats.activeStudentsToday}  icon={<Icon name="auto_stories" />} color="orange" href="/analytics" subtitle={activeSubtitle} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Weekly Engagement Chart */}
        <div className="lg:col-span-2">
          <Card className="h-full flex flex-col">
            <div className="flex items-start justify-between mb-4">
              <div>
                <h2 className="text-lg font-bold text-charcoal">Weekly Reading Activity</h2>
                {weekRangeLabel && (
                  <p className="text-xs text-text-secondary mt-0.5">{weekRangeLabel}</p>
                )}
              </div>
              <div className="text-right">
                <div className="text-[22px] font-extrabold text-charcoal leading-tight">{weekTotal}</div>
                <div className="text-xs text-text-secondary">logs this week</div>
              </div>
            </div>
            <div className="flex-1 min-h-0">
              <WeeklyChart data={weeklyEngagement} />
            </div>
          </Card>
        </div>

        {/* Right column: Shortcuts + Recent Activity — matching Card containers */}
        <div className="flex flex-col gap-6 min-w-0">
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-3">Shortcuts</h2>
            <div className="grid grid-cols-2 gap-2">
              {shortcuts.map((action) => (
                <Link
                  key={action.href}
                  href={action.href}
                  className="flex items-center gap-2.5 p-2.5 rounded-[var(--radius-md)] bg-background hover:bg-rose-pink/5 transition-colors"
                >
                  <span className={`inline-flex items-center justify-center w-8 h-8 rounded-[var(--radius-md)] flex-shrink-0 ${action.colorClass}`}>
                    {action.icon}
                  </span>
                  <span className="text-sm font-semibold text-charcoal truncate">{action.label}</span>
                </Link>
              ))}
            </div>
          </Card>

          <Card className="flex-1 flex flex-col min-h-0">
            <div className="flex items-center justify-between mb-3">
              <h2 className="text-lg font-bold text-charcoal">Recent Activity</h2>
              {recentActivity.length > 0 && (
                <Link href="/analytics" className="text-xs font-semibold text-rose-pink hover:underline">
                  View all
                </Link>
              )}
            </div>
            {recentActivity.length === 0 ? (
              <div className="flex-1 flex flex-col items-center justify-center text-center py-6">
                <span className="text-text-secondary/40 mb-2"><Icon name="history" size={28} /></span>
                <p className="text-sm font-semibold text-charcoal">Nothing yet today</p>
                <p className="text-xs text-text-secondary mt-0.5">Activity appears here as students log books.</p>
              </div>
            ) : (
              <ul className="space-y-3 overflow-y-auto flex-1 -mr-2 pr-2">
                {recentActivity.map((activity) => (
                  <li key={activity.id} className="flex items-start gap-3">
                    <div className="w-9 h-9 rounded-full bg-mint-green/30 flex items-center justify-center flex-shrink-0 text-mint-green-dark">
                      <Icon name="menu_book" size={18} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-charcoal truncate">{activity.studentName}</p>
                      <p className="text-xs text-text-secondary truncate">
                        {activity.action}{activity.bookTitle ? ` · ${activity.bookTitle}` : ''}
                      </p>
                    </div>
                    <span className="text-xs text-text-secondary flex-shrink-0 whitespace-nowrap">{formatRelativeTime(activity.time)}</span>
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
