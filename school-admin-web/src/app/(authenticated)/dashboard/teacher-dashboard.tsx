'use client';

import { StatCard } from '@/components/lumi/stat-card';
import { Card } from '@/components/lumi/card';
import { Badge } from '@/components/lumi/badge';
import { Icon } from '@/components/lumi/icon';
import { WeeklyChart } from './weekly-chart';
import { getGreeting } from '@/lib/utils/formatters';
import Link from 'next/link';
import type { TeacherDashboardData, WeeklyEngagement } from '@/lib/firestore/dashboard';

interface TeacherDashboardProps {
  userName: string;
  data: TeacherDashboardData;
  weeklyEngagement: WeeklyEngagement[];
}

export function TeacherDashboard({ userName, data, weeklyEngagement }: TeacherDashboardProps) {
  const firstName = userName.split(' ')[0];

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

      {/* Stats Grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        <StatCard title="Total Students" value={data.totalStudents} icon={<Icon name="person" />} color="pink" />
        <StatCard title="Read Today" value={data.readToday} icon={<Icon name="auto_stories" />} color="green" />
        <StatCard title="On Streak" value={data.onStreak} icon={<Icon name="local_fire_department" />} color="orange" />
        <StatCard title="Books Today" value={data.booksToday} icon={<Icon name="library_books" />} color="blue" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Weekly Chart */}
        <div className="lg:col-span-2">
          <Card>
            <h2 className="text-lg font-bold text-charcoal mb-4">This Week</h2>
            <WeeklyChart data={weeklyEngagement} />
          </Card>
        </div>

        {/* Class Cards */}
        <div className="space-y-4">
          <h2 className="text-lg font-bold text-charcoal">Your Classes</h2>
          {data.classes.length === 0 ? (
            <Card>
              <p className="text-sm text-text-secondary text-center py-4">No classes assigned yet</p>
            </Card>
          ) : (
            data.classes.map((cls) => (
              <Link key={cls.id} href={`/classes/${cls.id}`}>
                <Card hover>
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-[15px] font-bold text-charcoal">{cls.name}</h3>
                    {cls.yearLevel && <Badge variant="info">{cls.yearLevel}</Badge>}
                  </div>
                  <div className="flex items-center gap-4 text-xs text-text-secondary">
                    <span className="inline-flex items-center gap-1"><Icon name="person" size={14} /> {cls.studentCount} students</span>
                    <span className="inline-flex items-center gap-1"><Icon name="auto_stories" size={14} /> {cls.readTodayCount} read today</span>
                  </div>
                </Card>
              </Link>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
