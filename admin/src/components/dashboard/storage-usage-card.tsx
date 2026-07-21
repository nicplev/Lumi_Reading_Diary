"use client";

import Link from "next/link";
import { HardDrive } from "lucide-react";
import { SparkAreaChart } from "@tremor/react";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn, formatBytes, formatRelative } from "@/lib/utils";
import type { StorageSection } from "@/lib/dashboard/types";

const CATEGORY_LABELS: Record<string, string> = {
  comprehensionAudio: "Audio recordings",
  communityBookCovers: "Covers (app)",
  bookCovers: "Covers (portal)",
  schoolLogos: "School logos",
  other: "Other",
};

const STATUS_STYLES: Record<string, string> = {
  ok: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  warn: "bg-amber-100 text-amber-800 dark:bg-amber-900 dark:text-amber-200",
  critical: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  unknown: "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200",
};

export function StorageUsageCard({ storage }: { storage: StorageSection }) {
  if (!storage.available) {
    return (
      <Card>
        <CardHeader className="flex flex-row items-center justify-between space-y-0">
          <CardTitle>Audio Storage</CardTitle>
          <HardDrive className="h-4 w-4 text-muted-foreground" />
        </CardHeader>
        <CardContent>
          <p className="text-sm text-muted-foreground">
            Not yet seeded — deploy the storage-usage functions and run the
            first reconcile to populate totals.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card
      className={cn(
        storage.status === "warn" && "ring-amber-500/50",
        storage.status === "critical" && "ring-red-500/60"
      )}
    >
      <CardHeader className="flex flex-row items-center justify-between space-y-0">
        <CardTitle>Audio Storage</CardTitle>
        <Badge className={STATUS_STYLES[storage.status]}>
          {storage.status === "unknown" ? "no thresholds" : storage.status}
        </Badge>
      </CardHeader>
      <CardContent className="space-y-4">
        <div>
          <div className="text-2xl font-bold">
            {formatBytes(storage.audioBytes)}
          </div>
          <p className="text-xs text-muted-foreground">
            {storage.audioObjects.toLocaleString()} recordings ·{" "}
            {formatBytes(storage.totalBytes)} total in bucket (
            {storage.totalObjects.toLocaleString()} objects)
          </p>
        </div>

        {storage.history.length >= 2 && (
          <SparkAreaChart
            data={storage.history}
            index="date"
            categories={["audioBytes"]}
            colors={["blue"]}
            className="h-10 w-full"
          />
        )}

        <div className="space-y-1">
          {Object.entries(storage.categories)
            .sort(([, a], [, b]) => b.bytes - a.bytes)
            .map(([key, usage]) => (
              <div
                key={key}
                className="flex items-center justify-between text-xs"
              >
                <span className="text-muted-foreground">
                  {CATEGORY_LABELS[key] ?? key}
                </span>
                <span className="font-medium">
                  {formatBytes(usage.bytes)}{" "}
                  <span className="text-muted-foreground">
                    ({usage.objects.toLocaleString()})
                  </span>
                </span>
              </div>
            ))}
        </div>

        {storage.topSchools.length > 0 && (
          <div>
            <p className="mb-1 text-xs font-medium">Top audio consumers</p>
            <div className="space-y-1">
              {storage.topSchools.map((school) => (
                <div
                  key={school.schoolId}
                  className="flex items-center justify-between text-xs"
                >
                  <Link
                    href={`/schools/${encodeURIComponent(school.schoolId)}`}
                    className="truncate text-muted-foreground hover:text-foreground hover:underline"
                  >
                    {school.schoolName}
                  </Link>
                  <span className="font-medium">
                    {formatBytes(school.bytes)}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        <p className="text-xs text-muted-foreground">
          {storage.thresholds
            ? `Warn at ${formatBytes(storage.thresholds.warnBytes)} · critical at ${formatBytes(storage.thresholds.criticalBytes)}`
            : "No alert thresholds set (Operations → Feature Controls)"}
          {storage.lastReconcileAt && (
            <>
              {" · "}reconciled {formatRelative(storage.lastReconcileAt)}
              {storage.driftBytes !== null &&
                storage.driftBytes !== 0 &&
                ` (healed ${formatBytes(Math.abs(storage.driftBytes))} drift)`}
            </>
          )}
        </p>
        <Link
          href="/operations/feature-controls"
          className="inline-flex text-xs font-medium text-primary hover:underline"
        >
          Manage retention and storage thresholds
        </Link>
      </CardContent>
    </Card>
  );
}
