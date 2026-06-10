"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Mic } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";
import { formatDate } from "@/lib/utils";
import type { ComprehensionRecordingFlag } from "@lumi/server-ops";

interface Props {
  initialFlag: ComprehensionRecordingFlag;
}

export function FeatureControlsPanel({ initialFlag }: Props) {
  const [flag, setFlag] = useState(initialFlag);
  const [confirmTarget, setConfirmTarget] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  const disabling = confirmTarget === false;

  const closeDialog = () => {
    if (saving) return;
    setConfirmTarget(null);
    setReason("");
  };

  const handleConfirm = async () => {
    if (confirmTarget === null) return;
    if (disabling && !reason.trim()) {
      toast.error("A reason is required when disabling");
      return;
    }
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/comprehension-recording", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          enabled: confirmTarget,
          reason: disabling ? reason.trim() : undefined,
        }),
      });
      const json = (await res.json()) as
        | ComprehensionRecordingFlag
        | { error?: string };
      if (!res.ok) {
        throw new Error(
          (json as { error?: string }).error ?? "Failed to update flag"
        );
      }
      setFlag(json as ComprehensionRecordingFlag);
      toast.success(
        confirmTarget
          ? "Comprehension recording re-enabled platform-wide"
          : "Comprehension recording disabled platform-wide"
      );
      setConfirmTarget(null);
      setReason("");
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to update flag");
    } finally {
      setSaving(false);
    }
  };

  const provenance =
    flag.updatedAt &&
    `${flag.enabled ? "Enabled" : "Disabled"} by ${
      flag.updatedByEmail ?? flag.updatedBy ?? "unknown"
    } on ${formatDate(flag.updatedAt)}${
      !flag.enabled && flag.reason ? ` — Reason: ${flag.reason}` : ""
    }`;

  return (
    <>
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-4">
          <div className="flex items-start gap-3">
            <Mic className="mt-1 h-5 w-5 text-muted-foreground" />
            <div>
              <CardTitle className="flex items-center gap-2 text-base">
                Comprehension Recording
                <Badge variant={flag.enabled ? "secondary" : "destructive"}>
                  {flag.enabled ? "Enabled" : "Disabled platform-wide"}
                </Badge>
              </CardTitle>
              <CardDescription className="mt-1 max-w-2xl">
                Master switch for the voice-recording step in the parent
                reading-log wizard. While off, the step is hidden in every
                school regardless of the school&apos;s own setting, school
                admins cannot enable it, and audio uploads are rejected at the
                Storage layer — including from apps that haven&apos;t refreshed
                yet.
              </CardDescription>
            </div>
          </div>
          <Switch
            checked={flag.enabled}
            disabled={saving}
            onCheckedChange={(next) => setConfirmTarget(next)}
            aria-label="Toggle comprehension recording platform-wide"
          />
        </CardHeader>
        {provenance && (
          <CardContent>
            <p className="text-sm text-muted-foreground">{provenance}</p>
          </CardContent>
        )}
      </Card>

      <Dialog
        open={confirmTarget !== null}
        onOpenChange={(open) => {
          if (!open) closeDialog();
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {disabling
                ? "Disable comprehension recording everywhere?"
                : "Re-enable comprehension recording?"}
            </DialogTitle>
            <DialogDescription>
              {disabling
                ? "This hides the recording step from parents and the question tile from teachers in ALL schools, blocks school admins from turning it on, and rejects audio uploads at the Storage layer — even from stale clients. Each school's saved preference is kept and applies again on re-enable."
                : "Schools that had comprehension recording turned on will get it back automatically. School admins will be able to manage their own setting again."}
            </DialogDescription>
          </DialogHeader>
          {disabling && (
            <div className="space-y-2 py-2">
              <Label htmlFor="kill-switch-reason">Reason (required)</Label>
              <Textarea
                id="kill-switch-reason"
                placeholder="e.g. Storage costs spiking — investigating runaway uploads"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                maxLength={500}
                autoFocus
              />
            </div>
          )}
          <DialogFooter>
            <Button variant="ghost" onClick={closeDialog} disabled={saving}>
              Cancel
            </Button>
            <Button
              variant={disabling ? "destructive" : "default"}
              onClick={handleConfirm}
              disabled={saving || (disabling && !reason.trim())}
            >
              {saving
                ? "Saving…"
                : disabling
                  ? "Disable everywhere"
                  : "Re-enable"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
