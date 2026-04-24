"use client";

import { useState } from "react";
import { School, Users, Clock, UserCheck } from "lucide-react";
import { AreaChart, BarChart } from "@tremor/react";
import { StatCard } from "@/components/cards/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DateRangePicker,
  type DateRangePreset,
} from "@/components/charts/date-range-picker";
import type { CrossSchoolAnalyticsData } from "@/lib/firestore/analytics";

interface CrossSchoolDashboardProps {
  initialData: CrossSchoolAnalyticsData;
}

export function CrossSchoolDashboard({
  initialData,
}: CrossSchoolDashboardProps) {
  const now = new Date();
  const defaultStart = new Date(now);
  defaultStart.setDate(now.getDate() - 30);

  const [data, setData] = useState(initialData);
  const [loading, setLoading] = useState(false);
  const [startDate, setStartDate] = useState(
    defaultStart.toISOString().split("T")[0]
  );
  const [endDate, setEndDate] = useState(
    now.toISOString().split("T")[0]
  );
  const [preset, setPreset] = useState<DateRangePreset>("last30");

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
      const res = await fetch(`/api/analytics?${params.toString()}`);
      if (!res.ok) throw new Error("Failed to fetch");
      const result = await res.json();
      setData(result);
    } catch {
      // Keep existing data
    } finally {
      setLoading(false);
    }
  };

  const { overview } = data;

  return (
    <div className="space-y-6">
      <DateRangePicker
        startDate={startDate}
        endDate={endDate}
        preset={preset}
        onRangeChange={handleRangeChange}
        loading={loading}
      />

      {/* Overview Stats */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          title="Active Schools"
          value={overview.totalActiveSchools}
          icon={School}
        />
        <StatCard
          title="Total Students"
          value={overview.totalStudents.toLocaleString()}
          icon={Users}
        />
        <StatCard
          title="Minutes Read"
          value={overview.totalMinutesRead.toLocaleString()}
          icon={Clock}
        />
        <StatCard
          title="Total Parents"
          value={overview.totalParents.toLocaleString()}
          icon={UserCheck}
        />
      </div>

      {/* School Comparison Table */}
      <Card>
        <CardHeader>
          <CardTitle>School Comparison</CardTitle>
        </CardHeader>
        <CardContent>
          {data.schoolComparison.length === 0 ? (
            <p className="text-sm text-muted-foreground">No schools.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-left text-muted-foreground">
                    <th className="pb-2 pr-4">School</th>
                    <th className="pb-2 pr-4">Students</th>
                    <th className="pb-2 pr-4">Active</th>
                    <th className="pb-2 pr-4">Total Min</th>
                    <th className="pb-2 pr-4">Avg Min</th>
                    <th className="pb-2 pr-4">Completion</th>
                    <th className="pb-2">Parent Link</th>
                  </tr>
                </thead>
                <tbody>
                  {data.schoolComparison.map((s) => (
                    <tr key={s.schoolId} className="border-b">
                      <td className="py-2 pr-4 font-medium">
                        {s.schoolName}
                      </td>
                      <td className="py-2 pr-4">{s.studentCount}</td>
                      <td className="py-2 pr-4">{s.activeReaders}</td>
                      <td className="py-2 pr-4">
                        {s.totalMinutes.toLocaleString()}
                      </td>
                      <td className="py-2 pr-4">{s.avgMinutesPerStudent}</td>
                      <td className="py-2 pr-4">
                        {Math.round(s.completionRate * 100)}%
                      </td>
                      <td className="py-2">
                        {Math.round(s.parentLinkRate * 100)}%
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Onboarding Funnel + Growth Trends */}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Onboarding Funnel</CardTitle>
          </CardHeader>
          <CardContent>
            {data.onboardingFunnel.length === 0 ? (
              <p className="text-sm text-muted-foreground">No data.</p>
            ) : (
              <BarChart
                data={data.onboardingFunnel}
                index="stage"
                categories={["count"]}
                colors={["violet"]}
                yAxisWidth={36}
                showAnimation
                className="h-64"
              />
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Growth Trends</CardTitle>
          </CardHeader>
          <CardContent>
            {data.growthTrends.length === 0 ? (
              <p className="text-sm text-muted-foreground">No data.</p>
            ) : (
              <AreaChart
                data={data.growthTrends}
                index="date"
                categories={["newSchools", "newStudents", "newParents"]}
                colors={["blue", "emerald", "amber"]}
                yAxisWidth={36}
                showAnimation
                className="h-64"
              />
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
