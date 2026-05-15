"use client";

import { useState } from "react";
import { Users, Clock, BookOpen, CheckCircle } from "lucide-react";
import { StatCard } from "@/components/cards/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DateRangePicker,
  getDefaultRange,
  type DateRangePreset,
} from "@/components/charts/date-range-picker";
import { ReadingTrendChart } from "@/components/charts/reading-trend-chart";
import { LevelDistributionChart } from "@/components/charts/level-distribution-chart";
import { EngagementDonut } from "@/components/charts/engagement-donut";
import type { SchoolAnalyticsData } from "@/lib/firestore/analytics";

interface SchoolAnalyticsDashboardProps {
  schoolId: string;
  initialData: SchoolAnalyticsData;
}

export function SchoolAnalyticsDashboard({
  schoolId,
  initialData,
}: SchoolAnalyticsDashboardProps) {
  const defaultRange = getDefaultRange();
  const [data, setData] = useState(initialData);
  const [loading, setLoading] = useState(false);
  const [startDate, setStartDate] = useState(defaultRange.start);
  const [endDate, setEndDate] = useState(defaultRange.end);
  const [preset, setPreset] = useState<DateRangePreset>("thisWeek");

  const handleRangeChange = async (
    start: string,
    end: string,
    p: DateRangePreset
  ) => {
    setStartDate(start);
    setEndDate(end);
    setPreset(p);

    if (!start || !end) return;

    setLoading(true);
    try {
      const params = new URLSearchParams({ startDate: start, endDate: end });
      const res = await fetch(
        `/api/schools/${schoolId}/analytics?${params.toString()}`
      );
      if (!res.ok) throw new Error("Failed to fetch");
      const result = await res.json();
      setData(result);
    } catch {
      // Keep existing data on error
    } finally {
      setLoading(false);
    }
  };

  const { engagement } = data;

  return (
    <div className="space-y-6">
      <DateRangePicker
        startDate={startDate}
        endDate={endDate}
        preset={preset}
        onRangeChange={handleRangeChange}
        loading={loading}
      />

      {/* Engagement Stats */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          title="Active Readers"
          value={`${engagement.activeReaders} / ${engagement.totalStudents}`}
          icon={Users}
        />
        <StatCard
          title="Total Minutes"
          value={engagement.totalMinutes.toLocaleString()}
          icon={Clock}
        />
        <StatCard
          title="Avg Min / Student"
          value={engagement.avgMinutesPerStudent}
          icon={BookOpen}
        />
        <StatCard
          title="Completion Rate"
          value={`${Math.round(engagement.completionRate * 100)}%`}
          icon={CheckCircle}
        />
      </div>

      {/* Charts Row */}
      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <ReadingTrendChart data={data.readingTrend} />
        </div>
        <EngagementDonut
          completionRate={engagement.completionRate}
          totalLogs={engagement.totalLogs}
        />
      </div>

      {/* Level Distribution */}
      <LevelDistributionChart data={data.levelDistribution} />

      {/* Class Comparison */}
      <Card>
        <CardHeader>
          <CardTitle>Class Comparison</CardTitle>
        </CardHeader>
        <CardContent>
          {data.classComparison.length === 0 ? (
            <p className="text-sm text-muted-foreground">No class data.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="pb-2 pr-4">Class</th>
                    <th className="pb-2 pr-4">Students</th>
                    <th className="pb-2 pr-4">Active</th>
                    <th className="pb-2 pr-4">Total Min</th>
                    <th className="pb-2 pr-4">Avg Min</th>
                    <th className="pb-2">Completion</th>
                  </tr>
                </thead>
                <tbody>
                  {data.classComparison.map((c) => (
                    <tr key={c.classId} className="border-b">
                      <td className="py-2 pr-4 font-medium">{c.className}</td>
                      <td className="py-2 pr-4">{c.studentCount}</td>
                      <td className="py-2 pr-4">{c.activeReaders}</td>
                      <td className="py-2 pr-4">
                        {c.totalMinutes.toLocaleString()}
                      </td>
                      <td className="py-2 pr-4">{c.avgMinutesPerStudent}</td>
                      <td className="py-2">
                        {Math.round(c.completionRate * 100)}%
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Top Performers & Needs Support */}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Top Performers</CardTitle>
          </CardHeader>
          <CardContent>
            {data.topPerformers.length === 0 ? (
              <p className="text-sm text-muted-foreground">No data.</p>
            ) : (
              <div className="space-y-2">
                {data.topPerformers.map((s) => (
                  <div
                    key={s.studentId}
                    className="flex items-center justify-between rounded-md border p-2"
                  >
                    <div>
                      <p className="text-sm font-medium">
                        {s.firstName} {s.lastName}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Level: {s.currentReadingLevel ?? "\u2014"} | Streak:{" "}
                        {s.currentStreak}d
                      </p>
                    </div>
                    <p className="text-sm font-bold">
                      {s.totalMinutes} min
                    </p>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Needs Support</CardTitle>
          </CardHeader>
          <CardContent>
            {data.needsSupport.length === 0 ? (
              <p className="text-sm text-muted-foreground">No data.</p>
            ) : (
              <div className="space-y-2">
                {data.needsSupport.map((s) => (
                  <div
                    key={s.studentId}
                    className="flex items-center justify-between rounded-md border p-2"
                  >
                    <div>
                      <p className="text-sm font-medium">
                        {s.firstName} {s.lastName}
                      </p>
                      <p className="text-xs text-muted-foreground">
                        Level: {s.currentReadingLevel ?? "\u2014"} | Logs:{" "}
                        {s.logCount}
                      </p>
                    </div>
                    <p className="text-sm font-bold">
                      {s.totalMinutes} min
                    </p>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
