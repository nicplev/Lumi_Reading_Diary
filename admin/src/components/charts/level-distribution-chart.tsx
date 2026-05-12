"use client";

import { BarChart } from "@tremor/react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { LevelDistributionItem } from "@/lib/firestore/analytics";

interface LevelDistributionChartProps {
  data: LevelDistributionItem[];
}

export function LevelDistributionChart({ data }: LevelDistributionChartProps) {
  if (data.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Reading Level Distribution</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            No student data available.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Reading Level Distribution</CardTitle>
      </CardHeader>
      <CardContent>
        <BarChart
          data={data}
          index="level"
          categories={["count"]}
          colors={["indigo"]}
          yAxisWidth={36}
          showAnimation
          className="h-72"
        />
      </CardContent>
    </Card>
  );
}
