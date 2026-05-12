"use client";

import { DonutChart } from "@tremor/react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

interface EngagementDonutProps {
  completionRate: number;
  totalLogs: number;
}

export function EngagementDonut({
  completionRate,
  totalLogs,
}: EngagementDonutProps) {
  if (totalLogs === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Completion Rate</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            No reading logs for this period.
          </p>
        </CardContent>
      </Card>
    );
  }

  const completed = Math.round(completionRate * totalLogs);
  const other = totalLogs - completed;

  const data = [
    { name: "Completed", value: completed },
    { name: "Other", value: other },
  ];

  return (
    <Card>
      <CardHeader>
        <CardTitle>Completion Rate</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col items-center">
        <DonutChart
          data={data}
          index="name"
          category="value"
          colors={["emerald", "gray"]}
          showAnimation
          className="h-40"
        />
        <p className="mt-2 text-2xl font-bold">
          {Math.round(completionRate * 100)}%
        </p>
        <p className="text-sm text-muted-foreground">
          {completed} of {totalLogs} logs completed
        </p>
      </CardContent>
    </Card>
  );
}
