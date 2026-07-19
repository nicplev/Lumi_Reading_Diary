"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { formatDateTime } from "@/lib/utils";
import type {
  ComprehensionRetentionConfig,
  RunRetentionNowOutcome,
} from "@lumi/server-ops";

// UI guidance only. The API independently enforces the authoritative 30–730 day
// bounds, so these values are not part of the security boundary.
const MIN_RETENTION_DAYS = 30;
const MAX_RETENTION_DAYS = 730;

interface Props {
  initialConfig: ComprehensionRetentionConfig;
}

export function RetentionControlsCard({ initialConfig }: Props) {
  const [config, setConfig] = useState(initialConfig);
  const [daysInput, setDaysInput] = useState(String(initialConfig.retentionDays));
  const [saving, setSaving] = useState(false);
  const [running, setRunning] = useState(false);

  const parsedDays = Number(daysInput);
  const daysValid =
    Number.isInteger(parsedDays) &&
    parsedDays >= MIN_RETENTION_DAYS &&
    parsedDays <= MAX_RETENTION_DAYS;

  const dirty = parsedDays !== config.retentionDays;

  const handleSave = async () => {
    if (!daysValid) {
      toast.error(
        `Retention days must be an integer between ${MIN_RETENTION_DAYS} and ${MAX_RETENTION_DAYS}`
      );
      return;
    }
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/comprehension-retention", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ retentionDays: parsedDays }),
      });
      const json = (await res.json()) as
        | ComprehensionRetentionConfig
        | { error?: string };
      if (!res.ok) {
        throw new Error(
          (json as { error?: string }).error ?? "Failed to save retention config"
        );
      }
      const next = json as ComprehensionRetentionConfig;
      setConfig(next);
      setDaysInput(String(next.retentionDays));
      toast.success("Retention policy saved");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  };

  const handleRunNow = async () => {
    setRunning(true);
    try {
      const res = await fetch(
        "/api/platform-config/comprehension-retention/run-now",
        { method: "POST" }
      );
      const json = (await res.json()) as
        | RunRetentionNowOutcome
        | { error?: string };
      if (!res.ok) {
        throw new Error(
          (json as { error?: string }).error ?? "Run failed"
        );
      }
      const stats = json as RunRetentionNowOutcome;
      toast.success(
        `Run complete — deleted ${stats.deletedCount}, failed ${stats.failedCount}`
      );
      // Refresh server-rendered state so lastRun timestamp shows up
      // without a hard reload.
      const refreshed = await fetch(
        "/api/platform-config/comprehension-retention"
      ).then((r) => r.json() as Promise<ComprehensionRetentionConfig>);
      setConfig(refreshed);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Run failed");
    } finally {
      setRunning(false);
    }
  };

  const lastRun = config.lastRunAt
    ? `${formatDateTime(config.lastRunAt)}${
        config.lastRunStats
          ? ` — deleted ${config.lastRunStats.deletedCount}, failed ${config.lastRunStats.failedCount}`
          : ""
      }`
    : "Never";

  const updated = config.updatedAt
    ? `Updated by ${config.updatedByEmail ?? config.updatedBy ?? "unknown"} on ${formatDateTime(config.updatedAt)}`
    : null;
  const stats = config.lastRunStats;
  const retentionBuckets = stats?.retentionPolicyCounts
    ? Object.entries(stats.retentionPolicyCounts)
        .sort(([a], [b]) => Number(a) - Number(b))
        .map(([days, count]) => `${days}d: ${count} school${count === 1 ? "" : "s"}`)
        .join(" · ")
    : null;

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <Trash2 className="mt-1 h-5 w-5 text-muted-foreground" />
          <div>
            <CardTitle className="flex items-center gap-2 text-base">
              Comprehension Audio Retention
              <Badge variant="secondary">Always active</Badge>
            </CardTitle>
            <CardDescription className="mt-1 max-w-2xl">
              Daily cleanup honours each school&apos;s 30, 90 or 365-day choice.
              This value is used only when a school has no valid stored choice.
              Reading logs are preserved; only audio and its receipt fields are
              removed. Cleanup cannot be disabled from the portal.
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="space-y-2">
          <Label htmlFor="retention-days" className="text-sm">
            Fallback retention (days)
          </Label>
          <Input
            id="retention-days"
            type="number"
            inputMode="numeric"
            min={MIN_RETENTION_DAYS}
            max={MAX_RETENTION_DAYS}
            step={1}
            value={daysInput}
            disabled={saving}
            onChange={(e) => setDaysInput(e.target.value)}
            className="max-w-[200px]"
          />
          <p className="text-xs text-muted-foreground">
            Between {MIN_RETENTION_DAYS} and {MAX_RETENTION_DAYS} days. This
            does not replace a school&apos;s explicit 30/90/365-day choice.
          </p>
        </div>

        <div className="space-y-1 border-t pt-4 text-xs text-muted-foreground">
          <p>
            <span className="font-medium">Last run:</span> {lastRun}
          </p>
          {retentionBuckets && <p>{retentionBuckets}</p>}
          {stats?.fallbackSchoolCount !== undefined && (
            <p>
              Platform fallback used by {stats.fallbackSchoolCount} school
              {stats.fallbackSchoolCount === 1 ? "" : "s"}.
            </p>
          )}
          {stats?.legacySevenDaySchoolCount !== undefined &&
            stats.legacySevenDaySchoolCount > 0 && (
              <p>
                Legacy 7-day deletion commitments still honoured for{" "}
                {stats.legacySevenDaySchoolCount} school
                {stats.legacySevenDaySchoolCount === 1 ? "" : "s"}; new
                collection requires a 30+ day choice.
              </p>
            )}
          {updated && <p>{updated}</p>}
        </div>

        <div className="flex justify-end gap-2">
          <Button
            variant="outline"
            onClick={handleRunNow}
            disabled={running || saving}
            title="Run the same cleanup the daily cron runs, attributed to you"
          >
            {running ? "Running…" : "Run now"}
          </Button>
          <Button
            onClick={handleSave}
            disabled={saving || !dirty || !daysValid}
          >
            {saving ? "Saving…" : "Save retention policy"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
