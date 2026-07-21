import Link from "next/link";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn, formatRelative } from "@/lib/utils";
import type { HealthSection, CronHealth } from "@/lib/dashboard/types";

function cronDotClass(cron: CronHealth): string {
  if (cron.lastStatus === "error") return "bg-red-500";
  if (cron.freshness === "fresh") return "bg-green-500";
  if (cron.freshness === "stale") return "bg-amber-500";
  return "bg-gray-300 dark:bg-gray-600";
}

function FlagBadge({ label, on }: { label: string; on: boolean }) {
  return (
    <Badge
      className={cn(
        on
          ? "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
          : "bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200"
      )}
    >
      {label}: {on ? "on" : "off"}
    </Badge>
  );
}

export function SystemHealthCard({ health }: { health: HealthSection }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>System Health</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex flex-wrap gap-2">
          <FlagBadge
            label="Incremental student stats"
            on={health.incrementalAggregation.studentStats}
          />
          <FlagBadge
            label="Incremental class stats"
            on={health.incrementalAggregation.classStats}
          />
          <FlagBadge label="Audio retention" on={health.retention.enabled} />
        </div>

        <div className="space-y-1 text-xs text-muted-foreground">
          {health.retention.lastRunAt && (
            <p>
              Retention last ran {formatRelative(health.retention.lastRunAt)}
              {health.retention.deletedCount !== null &&
                ` — ${health.retention.deletedCount} deleted, ${health.retention.failedCount ?? 0} failed`}
            </p>
          )}
          {health.statsReconcileUpdatedAt && (
            <p>
              Stats reconciler cursor moved{" "}
              {formatRelative(health.statsReconcileUpdatedAt)}
            </p>
          )}
        </div>

        <div className="space-y-1.5">
          {health.crons.map((cron) => (
            <div
              key={cron.name}
              className="flex items-center justify-between gap-2 text-xs"
            >
              <div className="flex min-w-0 items-center gap-2">
                <span
                  className={cn(
                    "h-2 w-2 shrink-0 rounded-full",
                    cronDotClass(cron)
                  )}
                />
                <span className="truncate font-medium">{cron.label}</span>
                <span className="shrink-0 text-muted-foreground">
                  {cron.scheduleLabel}
                </span>
              </div>
              <span
                className={cn(
                  "shrink-0",
                  cron.freshness === "stale" || cron.lastStatus === "error"
                    ? "font-medium text-amber-600 dark:text-amber-400"
                    : "text-muted-foreground"
                )}
                title={cron.note ?? undefined}
              >
                {cron.lastRunAt
                  ? formatRelative(cron.lastRunAt)
                  : "no heartbeat"}
              </span>
            </div>
          ))}
        </div>
        <Link
          href="/operations/feature-controls"
          className="inline-flex text-xs font-medium text-primary hover:underline"
        >
          Manage feature controls
        </Link>
      </CardContent>
    </Card>
  );
}
