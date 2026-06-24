'use client';

import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { WeeklyChart } from './weekly-chart';
import { CustomizableWidgets, type DashboardWidgetDef } from './customizable-widgets';
import { getGreeting } from '@/lib/utils/formatters';
import { useAuth } from '@/lib/auth/auth-context';
import Link from 'next/link';
import type { TeacherDashboardData, WeeklyEngagement } from '@/lib/firestore/dashboard';

interface DashboardWidgets {
  topReaders: { studentId: string; name: string; minutes: number }[];
  nudges: { studentId: string; name: string; daysSinceRead: number | null }[];
  parentComments: { logId: string; studentId: string; studentName: string; preview: string; at: string }[];
}

interface TeacherDashboardProps {
  userName: string;
  data: TeacherDashboardData;
  weeklyEngagement: WeeklyEngagement[];
  widgets: DashboardWidgets;
}

export function TeacherDashboard({ userName, data, weeklyEngagement, widgets }: TeacherDashboardProps) {
  const { user } = useAuth();
  const firstName = userName.split(' ')[0];

  const widgetDefs: DashboardWidgetDef[] = [
    {
      id: 'weekly',
      title: 'This week',
      node: (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-4">This Week</h2>
          <WeeklyChart data={weeklyEngagement} />
        </Card>
      ),
    },
    {
      id: 'classes',
      title: 'Your classes',
      node: (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-3">Your Classes</h2>
          {data.classes.length === 0 ? (
            <p className="text-sm text-text-secondary">No classes assigned yet.</p>
          ) : (
            <div className="space-y-1">
              {data.classes.map((cls) => (
                <Link
                  key={cls.id}
                  href={`/classes/${cls.id}`}
                  className="block hover:bg-background rounded-[var(--radius-md)] p-2 -mx-2 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-bold text-charcoal">{cls.name}</span>
                    {cls.yearLevel && <Badge variant="info">{cls.yearLevel}</Badge>}
                  </div>
                  <div className="flex items-center gap-3 text-xs text-text-secondary mt-0.5">
                    <span className="inline-flex items-center gap-1">
                      <Icon name="person" size={12} /> {cls.studentCount}
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <Icon name="auto_stories" size={12} /> {cls.readTodayCount} today
                    </span>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </Card>
      ),
    },
    {
      id: 'topReaders',
      title: 'Top readers',
      node: (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-3">Top readers this week</h2>
          {widgets.topReaders.length === 0 ? (
            <p className="text-sm text-text-secondary">No reading logged yet this week.</p>
          ) : (
            <ul className="space-y-2">
              {widgets.topReaders.map((r, i) => (
                <li key={r.studentId}>
                  <Link
                    href={`/students/${r.studentId}`}
                    className="flex items-center justify-between hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                  >
                    <span className="text-sm text-charcoal font-medium truncate">
                      <span className="text-text-secondary mr-1.5">{i + 1}.</span>
                      {r.name}
                    </span>
                    <span className="text-xs text-text-secondary whitespace-nowrap">{r.minutes} min</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ),
    },
    {
      id: 'nudges',
      title: 'Needs attention',
      node: (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-3">Needs attention</h2>
          {widgets.nudges.length === 0 ? (
            <p className="text-sm text-text-secondary">Everyone has read recently. 🎉</p>
          ) : (
            <ul className="space-y-2">
              {widgets.nudges.map((n) => (
                <li key={n.studentId}>
                  <Link
                    href={`/students/${n.studentId}`}
                    className="flex items-center justify-between hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                  >
                    <span className="text-sm text-charcoal font-medium truncate">{n.name}</span>
                    <span className="text-xs text-text-secondary whitespace-nowrap">
                      {n.daysSinceRead === null ? 'Not read yet' : `${n.daysSinceRead}d ago`}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ),
    },
    {
      id: 'parentComments',
      title: 'Parent comments',
      node: (
        <Card>
          <h2 className="text-lg font-bold text-charcoal mb-3">New parent comments</h2>
          {widgets.parentComments.length === 0 ? (
            <p className="text-sm text-text-secondary">No new parent comments.</p>
          ) : (
            <ul className="space-y-2.5">
              {widgets.parentComments.map((c) => (
                <li key={c.logId}>
                  <Link
                    href={`/students/${c.studentId}`}
                    className="block hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                  >
                    <p className="text-sm font-medium text-charcoal truncate">{c.studentName}</p>
                    <p className="text-xs text-text-secondary truncate">{c.preview}</p>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      ),
    },
  ];

  return (
    <div>
      {/* Greeting */}
      <div className="mb-6">
        <h1 className="text-[28px] font-bold text-charcoal">
          {getGreeting()}, {firstName}
        </h1>
        <p className="text-sm text-text-secondary mt-1">
          {new Date().toLocaleDateString('en-AU', { weekday: 'long', day: 'numeric', month: 'long' })}
        </p>
      </div>

      {/* Stats Grid (fixed) */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard title="Total Students" value={data.totalStudents} icon={<Icon name="person" />} color="pink" />
        <StatCard title="Read Today" value={data.readToday} icon={<Icon name="auto_stories" />} color="green" />
        <StatCard title="On Streak" value={data.onStreak} icon={<Icon name="local_fire_department" />} color="orange" />
        <StatCard title="Books Today" value={data.booksToday} icon={<Icon name="library_books" />} color="blue" />
      </div>

      {/* Customizable widgets */}
      <CustomizableWidgets
        widgets={widgetDefs}
        storageKey={`lumi-teacher-dashboard-widgets:${user?.uid ?? 'anon'}`}
      />
    </div>
  );
}
