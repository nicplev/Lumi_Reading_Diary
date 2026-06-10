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
import { Switch } from "@/components/ui/switch";
import { formatDateTime } from "@/lib/utils";
import {
  MIN_RETENTION_DAYS,
  MAX_RETENTION_DAYS,
  type ComprehensionRetentionConfig,
} from "@lumi/server-ops";

interface Props {
  initialConfig: ComprehensionRetentionConfig;
}

export function RetentionControlsCard({ initialConfig }: Props) {
  const [config, setConfig] = useState(initialConfig);
  const [enabled, setEnabled] = useState(initialConfig.enabled);
  const [daysInput, setDaysInput] = useState(String(initialConfig.retentionDays));
  const [saving, setSaving] = useState(false);

  const parsedDays = Number(daysInput);
  const daysValid =
    Number.isInteger(parsedDays) &&
    parsedDays >= MIN_RETENTION_DAYS &&
    parsedDays <= MAX_RETENTION_DAYS;

  const dirty =
    enabled !== config.enabled || parsedDays !== config.retentionDays;

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
        body: JSON.stringify({ enabled, retentionDays: parsedDays }),
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
      setEnabled(next.enabled);
      setDaysInput(String(next.retentionDays));
      toast.success("Retention policy saved");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to save");
    } finally {
      setSaving(false);
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

  return (
    <Card>
      <CardHeader className="flex flex-row items-start justify-between gap-4">
        <div className="flex items-start gap-3">
          <Trash2 className="mt-1 h-5 w-5 text-muted-foreground" />
          <div>
            <CardTitle className="flex items-center gap-2 text-base">
              Comprehension Audio Retention
              <Badge variant={config.enabled ? "secondary" : "outline"}>
                {config.enabled ? "Active" : "Disabled"}
              </Badge>
            </CardTitle>
            <CardDescription className="mt-1 max-w-2xl">
              Daily cleanup that deletes comprehension audio Storage objects
              older than the configured number of days. The reading-log doc
              itself is preserved — only the audio file and its pointer fields
              are cleared. The cron writes a summary entry to{" "}
              <code>adminAuditLog</code> on every run.
            </CardDescription>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex items-center justify-between gap-4">
          <div>
            <Label htmlFor="retention-enabled" className="text-sm">
              Enable scheduled cleanup
            </Label>
            <p className="text-xs text-muted-foreground">
              While off, no recordings are deleted by the cron. Existing files
              remain in Storage.
            </p>
          </div>
          <Switch
            id="retention-enabled"
            checked={enabled}
            disabled={saving}
            onCheckedChange={setEnabled}
          />
        </div>

        <div className="space-y-2">
          <Label htmlFor="retention-days" className="text-sm">
            Retain for (days)
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
            Between {MIN_RETENTION_DAYS} and {MAX_RETENTION_DAYS} days.
            Recordings older than this are eligible for deletion on the next
            cron run.
          </p>
        </div>

        <div className="space-y-1 border-t pt-4 text-xs text-muted-foreground">
          <p>
            <span className="font-medium">Last run:</span> {lastRun}
          </p>
          {updated && <p>{updated}</p>}
        </div>

        <div className="flex justify-end">
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
