"use client";

import { AreaChart } from "@tremor/react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { DailyReadingPoint } from "@/lib/firestore/analytics";

interface ReadingTrendChartProps {
  data: DailyReadingPoint[];
}

export function ReadingTrendChart({ data }: ReadingTrendChartProps) {
  if (data.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Reading Trend</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            No reading data for this period.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Reading Trend</CardTitle>
      </CardHeader>
      <CardContent>
        <AreaChart
          data={data}
          index="date"
          categories={["minutes"]}
          colors={["blue"]}
          yAxisWidth={48}
          showAnimation
          className="h-72"
        />
      </CardContent>
    </Card>
  );
}
