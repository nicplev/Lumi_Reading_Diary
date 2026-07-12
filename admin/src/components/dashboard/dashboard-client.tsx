"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn, formatRelative } from "@/lib/utils";
import type { DashboardPayload } from "@/lib/dashboard/types";
import { KpiRow } from "./kpi-row";
import { ActivityTrendCard } from "./activity-trend-card";
import { StorageUsageCard } from "./storage-usage-card";
import { SystemHealthCard } from "./system-health-card";
import { AttentionListCard } from "./attention-list-card";
import { ActivityFeedTabs } from "./activity-feed-tabs";

const REFETCH_INTERVAL_MS = 45_000;

async function fetchDashboard(): Promise<DashboardPayload> {
  const res = await fetch("/api/dashboard");
  if (!res.ok) {
    throw new Error(`Dashboard fetch failed (${res.status})`);
  }
  return res.json();
}

export function DashboardClient({
  initialData,
}: {
  initialData: DashboardPayload;
}) {
  const { data, dataUpdatedAt, isFetching, isError, refetch } =
    useQuery<DashboardPayload>({
      queryKey: ["dashboard"],
      queryFn: fetchDashboard,
      initialData,
      staleTime: 30_000,
      // refetchIntervalInBackground defaults to false, so polling pauses
      // while the tab is hidden and resumes (plus refetches) on focus.
      refetchInterval: REFETCH_INTERVAL_MS,
      refetchOnWindowFocus: true,
    });

  // Re-render every 15s so the "updated Xs ago" stamp stays honest
  // between refetches.
  const [, setTick] = useState(0);
  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 15_000);
    return () => clearInterval(id);
  }, []);

  const payload = data ?? initialData;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">
          Live · updated{" "}
          {dataUpdatedAt ? formatRelative(new Date(dataUpdatedAt)) : "just now"}
          {" · "}auto-refreshes every {Math.round(REFETCH_INTERVAL_MS / 1000)}s
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => refetch()}
          disabled={isFetching}
        >
          <RefreshCw
            className={cn("mr-1 h-3.5 w-3.5", isFetching && "animate-spin")}
          />
          Refresh
        </Button>
      </div>

      {isError && (
        <div className="flex items-center gap-2 rounded-md border border-amber-500/50 bg-amber-50 px-3 py-2 text-sm text-amber-800 dark:bg-amber-950 dark:text-amber-200">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          Live refresh is failing — showing the last loaded data.
        </div>
      )}

      <KpiRow kpis={payload.kpis} />

      <div className="grid gap-4 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <ActivityTrendCard
            trend={payload.trend}
            totalMinutes={payload.totalTrendMinutes}
          />
        </div>
        <StorageUsageCard storage={payload.storage} />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <SystemHealthCard health={payload.health} />
        <AttentionListCard items={payload.attention} />
      </div>

      <div>
        <h2 className="mb-4 text-lg font-semibold">Recent Activity</h2>
        <ActivityFeedTabs activity={payload.activity} />
      </div>
    </div>
  );
}
