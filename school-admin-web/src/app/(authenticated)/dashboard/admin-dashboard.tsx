'use client';

import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { PageHeader } from '@/components/lumi/page-header';
import { Badge } from '@/components/lumi/badge';
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
  { label: 'Add User', href: '/users', icon: <Icon name="person_add" size={22} /> },
  { label: 'Add Class', href: '/classes', icon: <Icon name="school" size={22} /> },
  { label: 'Reports', href: '/analytics', icon: <Icon name="bar_chart" size={22} /> },
  { label: 'Parent Links', href: '/parent-links', icon: <Icon name="link" size={22} /> },
];

export function AdminDashboard({ schoolName, stats, weeklyEngagement, recentActivity }: AdminDashboardProps) {
  return (
    <div>
      <PageHeader
        title={schoolName}
        description="School administration dashboard"
      />

      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard title="Students" value={stats.totalStudents} icon={<Icon name="person" />} color="pink" href="/students" />
        <StatCard title="Teachers" value={stats.totalTeachers} icon={<Icon name="person" />} color="blue" href="/users" />
        <StatCard title="Classes" value={stats.totalClasses} icon={<Icon name="school" />} color="green" href="/classes" />
        <StatCard title="Active Today" value={stats.activeStudentsToday} icon={<Icon name="auto_stories" />} color="orange" href="/analytics" subtitle="as of today" sparklineData={weeklyEngagement.map(d => d.count)} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Weekly Engagement Chart */}
        <div className="lg:col-span-2">
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-4">Weekly Reading Activity</h2>
            <WeeklyChart data={weeklyEngagement} />
          </Card>
        </div>

        {/* Shortcuts + Recent Activity */}
        <div className="space-y-6">
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-3">Shortcuts</h2>
            <div className="grid grid-cols-2 gap-2">
              {shortcuts.map((action) => (
                <Link
                  key={action.href}
                  href={action.href}
                  className="flex flex-col items-center gap-1.5 p-3 rounded-[var(--radius-md)] bg-background hover:bg-rose-pink/5 transition-colors text-center"
                >
                  <span className="text-text-secondary">{action.icon}</span>
                  <span className="text-xs font-semibold text-text-secondary">{action.label}</span>
                </Link>
              ))}
            </div>
          </Card>

          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-3">Recent Activity</h2>
            {recentActivity.length === 0 ? (
              <p className="text-sm text-text-secondary py-4 text-center">No recent activity</p>
            ) : (
              <ul className="space-y-3">
                {recentActivity.map((activity) => (
                  <li key={activity.id} className="flex items-start gap-3">
                    <div className="w-8 h-8 rounded-full bg-mint-green/30 flex items-center justify-center flex-shrink-0 mt-0.5 text-mint-green-dark">
                      <Icon name="auto_stories" size={16} />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-charcoal truncate">{activity.studentName}</p>
                      <p className="text-xs text-text-secondary truncate">{activity.action}</p>
                    </div>
                    <Badge variant="default">{formatRelativeTime(activity.time)}</Badge>
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
