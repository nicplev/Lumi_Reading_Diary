'use client';

import { StatCard } from '@/components/lumi/stat-card';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { Avatar } from '@/components/lumi/avatar';
import { WeeklyChart } from './weekly-chart';
import { EngagementRing } from './widgets/engagement-ring';
import { SentimentBar } from './widgets/sentiment-bar';
import { RecentReading } from './widgets/recent-reading';
import { GroupComparison } from './widgets/group-comparison';
import { AchievementSpotlight } from './widgets/achievement-spotlight';
import { ReadingCalendar } from './widgets/reading-calendar';
import { CustomizableWidgets, type DashboardWidgetDef } from './customizable-widgets';
import { getGreeting } from '@/lib/utils/formatters';
import { useAuth } from '@/lib/auth/auth-context';
import Link from 'next/link';
import type { TeacherDashboardData, WeeklyEngagement } from '@/lib/firestore/dashboard';

interface DashboardWidgets {
  topReaders: { studentId: string; name: string; minutes: number; characterId?: string }[];
  nudges: { studentId: string; name: string; daysSinceRead: number | null; characterId?: string }[];
  parentComments: {
    logId: string;
    studentId: string;
    studentName: string;
    preview: string;
    at: string;
    characterId?: string;
  }[];
  sentiment: { feeling: string; count: number }[];
  recentReading: {
    logId: string;
    studentId: string;
    studentName: string;
    books: string[];
    minutes: number;
    at: string;
    characterId?: string;
  }[];
  groupComparison: {
    groupId: string;
    name: string;
    color: string | null;
    totalStudents: number;
    activeReaders: number;
    totalMinutes: number;
    avgMinutes: number;
  }[];
  recentAchievements: {
    studentId: string;
    studentName: string;
    name: string;
    icon: string;
    rarity: string;
    earnedAt: string | null;
    characterId?: string;
  }[];
}

interface TeacherDashboardProps {
  userName: string;
  data: TeacherDashboardData;
  weeklyEngagement: WeeklyEngagement[];
  widgets: DashboardWidgets;
}

/** Vertically-centred empty-state line so short cards don't look top-heavy when
 *  stretched to match a taller card in the same row. */
function EmptyMsg({ children }: { children: React.ReactNode }) {
  return <p className="text-sm text-text-secondary h-full flex items-center">{children}</p>;
}

export function TeacherDashboard({ userName, data, weeklyEngagement, widgets }: TeacherDashboardProps) {
  const { user } = useAuth();
  const firstName = userName.split(' ')[0];

  const widgetDefs: DashboardWidgetDef[] = [
    {
      id: 'weekly',
      title: 'This week',
      size: 'lg',
      body: <WeeklyChart data={weeklyEngagement} />,
    },
    {
      id: 'engagement',
      title: "Today's engagement",
      body: <EngagementRing readToday={data.readToday} totalStudents={data.totalStudents} />,
    },
    {
      id: 'classes',
      title: 'Your classes',
      action: (
        <Link href="/classes" className="text-xs font-semibold text-rose-pink hover:underline whitespace-nowrap">
          View all
        </Link>
      ),
      body:
        data.classes.length === 0 ? (
          <EmptyMsg>No classes assigned yet.</EmptyMsg>
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
        ),
    },
    {
      id: 'topReaders',
      title: 'Top readers',
      body:
        widgets.topReaders.length === 0 ? (
          <EmptyMsg>No reading logged yet this week.</EmptyMsg>
        ) : (
          <ul className="space-y-2">
            {widgets.topReaders.map((r, i) => (
              <li key={r.studentId}>
                <Link
                  href={`/students/${r.studentId}`}
                  className="flex items-center gap-2 hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                >
                  <span className="text-xs text-text-secondary w-4 text-right flex-shrink-0">{i + 1}</span>
                  <Avatar name={r.name} characterId={r.characterId} size="sm" className="flex-shrink-0" />
                  <span className="text-sm text-charcoal font-medium truncate flex-1">{r.name}</span>
                  <span className="text-xs text-text-secondary whitespace-nowrap">{r.minutes} min</span>
                </Link>
              </li>
            ))}
          </ul>
        ),
    },
    {
      id: 'recentReading',
      title: 'Recent reading',
      body: <RecentReading items={widgets.recentReading} />,
    },
    {
      id: 'nudges',
      title: 'Needs attention',
      body:
        widgets.nudges.length === 0 ? (
          <EmptyMsg>
            <Icon name="check_circle" size={16} className="text-mint-green-dark mr-1.5 flex-shrink-0" />
            Everyone has read recently.
          </EmptyMsg>
        ) : (
          <ul className="space-y-2 max-h-72 overflow-y-auto -mr-1 pr-1">
            {widgets.nudges.map((n) => (
              <li key={n.studentId}>
                <Link
                  href={`/students/${n.studentId}`}
                  className="flex items-center gap-2 hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                >
                  <Avatar name={n.name} characterId={n.characterId} size="sm" className="flex-shrink-0" />
                  <span className="text-sm text-charcoal font-medium truncate flex-1">{n.name}</span>
                  <span className="text-xs text-text-secondary whitespace-nowrap">
                    {n.daysSinceRead === null ? 'Not read yet' : `${n.daysSinceRead}d ago`}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        ),
    },
    {
      id: 'parentComments',
      title: 'Parent comments',
      body:
        widgets.parentComments.length === 0 ? (
          <EmptyMsg>No new parent comments.</EmptyMsg>
        ) : (
          <ul className="space-y-2.5 max-h-72 overflow-y-auto -mr-1 pr-1">
            {widgets.parentComments.map((c) => (
              <li key={c.logId}>
                <Link
                  href={`/students/${c.studentId}`}
                  className="flex items-start gap-2 hover:bg-background rounded-[var(--radius-sm)] px-1 py-1 -mx-1"
                >
                  <Avatar name={c.studentName} characterId={c.characterId} size="sm" className="flex-shrink-0 mt-0.5" />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-charcoal truncate">{c.studentName}</p>
                    <p className="text-xs text-text-secondary truncate">{c.preview}</p>
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        ),
    },
    {
      id: 'sentiment',
      title: 'How reading felt',
      body: <SentimentBar sentiment={widgets.sentiment} />,
    },
    {
      id: 'groupComparison',
      title: 'Reading groups',
      size: 'lg',
      body: <GroupComparison groups={widgets.groupComparison} />,
    },
    {
      id: 'achievements',
      title: 'Recent achievements',
      body: <AchievementSpotlight items={widgets.recentAchievements} />,
    },
    {
      id: 'readingCalendar',
      title: 'Reading calendar',
      size: 'lg',
      body: <ReadingCalendar />,
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
        defaultHidden={['sentiment', 'groupComparison', 'achievements', 'readingCalendar']}
      />
    </div>
  );
}
