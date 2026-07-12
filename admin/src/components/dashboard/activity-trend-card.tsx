"use client";

import { AreaChart } from "@tremor/react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { TrendPoint } from "@/lib/dashboard/types";

interface ActivityTrendCardProps {
  trend: TrendPoint[];
  totalMinutes: number;
}

export function ActivityTrendCard({ trend, totalMinutes }: ActivityTrendCardProps) {
  const totalLogs = trend.reduce((sum, p) => sum + p.logs, 0);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Reading Activity</CardTitle>
        <CardDescription>
          {totalLogs} logs · {totalMinutes.toLocaleString()} minutes over the
          last 14 days
        </CardDescription>
      </CardHeader>
      <CardContent>
        {totalLogs === 0 ? (
          <p className="text-sm text-muted-foreground">
            No reading logs in the last 14 days.
          </p>
        ) : (
          <AreaChart
            data={trend}
            index="date"
            categories={["logs"]}
            colors={["blue"]}
            yAxisWidth={40}
            showAnimation
            className="h-64"
          />
        )}
      </CardContent>
    </Card>
  );
}
