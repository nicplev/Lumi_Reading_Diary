"use client";

import { useState } from "react";
import { toast } from "sonner";
import { HardDrive } from "lucide-react";
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
import { formatBytes, formatDateTime } from "@/lib/utils";
import type {
  StorageAlertsConfig,
  StorageUsageReconcileStats,
} from "@lumi/server-ops";

const GIB = 1024 ** 3;

export interface StorageUsageSummary {
  audioBytes: number;
  totalBytes: number;
  lastReconcileAt: string | null;
}

interface Props {
  initialConfig: StorageAlertsConfig;
  usage: StorageUsageSummary | null;
}

function bytesToGbInput(bytes: number): string {
  return String(Math.round((bytes / GIB) * 100) / 100);
}

export function StorageAlertsCard({ initialConfig, usage: initialUsage }: Props) {
  const [config, setConfig] = useState(initialConfig);
  const [usage, setUsage] = useState(initialUsage);
  const [warnInput, setWarnInput] = useState(bytesToGbInput(initialConfig.warnBytes));
  const [criticalInput, setCriticalInput] = useState(
    bytesToGbInput(initialConfig.criticalBytes)
  );
  const [saving, setSaving] = useState(false);
  const [running, setRunning] = useState(false);

  const warnBytes = Math.round(Number(warnInput) * GIB);
  const criticalBytes = Math.round(Number(criticalInput) * GIB);
  const valid =
    Number.isFinite(warnBytes) &&
    Number.isFinite(criticalBytes) &&
    warnBytes > 0 &&
    criticalBytes > 0 &&
    warnBytes < criticalBytes;

  const dirty =
    !config.configured ||
    warnBytes !== config.warnBytes ||
    criticalBytes !== config.criticalBytes;

  const handleSave = async () => {
    if (!valid) {
      toast.error(
        "Thresholds must be positive and warn must be below critical"
      );
      return;
    }
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/storage-alerts", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ warnBytes, criticalBytes }),
      });
      const json = (await res.json()) as
        | StorageAlertsConfig
        | { error?: string };
      if (!res.ok) {
        throw new Error(
          (json as { error?: string }).error ?? "Failed to save thresholds"
        );
      }
      const next = json as StorageAlertsConfig;
      setConfig(next);
      setWarnInput(bytesToGbInput(next.warnBytes));
      setCriticalInput(bytesToGbInput(next.criticalBytes));
      toast.success("Storage alert thresholds saved");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  };

  const handleReconcileNow = async () => {
    setRunning(true);
    try {
      const res = await fetch("/api/storage-usage/reconcile", {
        method: "POST",
      });
      const json = (await res.json()) as
        | StorageUsageReconcileStats
        | { error?: string };
      if (!res.ok) {
        throw new Error((json as { error?: string }).error ?? "Scan failed");
      }
      const stats = json as StorageUsageReconcileStats;
      toast.success(
        `Scan complete — ${stats.scannedObjects} objects, ${formatBytes(stats.totalBytes)} total` +
          (stats.driftBytes !== 0
            ? `, healed ${formatBytes(Math.abs(stats.driftBytes))} drift`
            : "")
      );
      setUsage((prev) => ({
        audioBytes: prev?.audioBytes ?? 0,
        ...prev,
        totalBytes: stats.totalBytes,
        lastReconcileAt: new Date().toISOString(),
      }));
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Scan failed");
    } finally {
      setRunning(false);
    }
  };

  const updated = config.updatedAt
    ? `Updated by ${config.updatedByEmail ?? config.updatedBy ?? "unknown"} on ${formatDateTime(config.updatedAt)}`
    : null;

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <HardDrive className="mt-1 h-5 w-5 text-muted-foreground" />
          <div>
            <CardTitle className="flex items-center gap-2 text-base">
              Storage Alert Thresholds
              <Badge variant={config.configured ? "secondary" : "outline"}>
                {config.configured ? "Configured" : "Not set"}
              </Badge>
            </CardTitle>
            <CardDescription className="mt-1 max-w-2xl">
              The dashboard&apos;s audio-storage card turns amber past the warn
              threshold and red past critical. Thresholds compare against
              comprehension-audio bytes tracked in{" "}
              <code>opsMetrics/storageUsage</code> (live triggers + nightly
              reconcile).
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        {usage && (
          <p className="text-sm">
            Current usage:{" "}
            <span className="font-medium">{formatBytes(usage.audioBytes)}</span>{" "}
            audio · {formatBytes(usage.totalBytes)} total in bucket
            {usage.lastReconcileAt &&
              ` · last scan ${formatDateTime(usage.lastReconcileAt)}`}
          </p>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label htmlFor="warn-gb" className="text-sm">
              Warn at (GB)
            </Label>
            <Input
              id="warn-gb"
              type="number"
              inputMode="decimal"
              min={0.1}
              step={0.5}
              value={warnInput}
              disabled={saving}
              onChange={(e) => setWarnInput(e.target.value)}
              className="max-w-[200px]"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="critical-gb" className="text-sm">
              Critical at (GB)
            </Label>
            <Input
              id="critical-gb"
              type="number"
              inputMode="decimal"
              min={0.1}
              step={0.5}
              value={criticalInput}
              disabled={saving}
              onChange={(e) => setCriticalInput(e.target.value)}
              className="max-w-[200px]"
            />
          </div>
        </div>

        {updated && (
          <div className="border-t pt-4 text-xs text-muted-foreground">
            <p>{updated}</p>
          </div>
        )}

        <div className="flex justify-end gap-2">
          <Button
            variant="outline"
            onClick={handleReconcileNow}
            disabled={running || saving}
            title="Run the same full-bucket scan the nightly cron runs, attributed to you"
          >
            {running ? "Scanning…" : "Reconcile now"}
          </Button>
          <Button onClick={handleSave} disabled={saving || !dirty || !valid}>
            {saving ? "Saving…" : "Save thresholds"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
