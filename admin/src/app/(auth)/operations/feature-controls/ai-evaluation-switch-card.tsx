"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
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

export interface AiEvaluationFlagView {
  enabled: boolean;
  updatedAt: string | null;
  updatedByEmail?: string;
  reason?: string;
}

// Platform-wide AI comprehension-evaluation kill switch
// (platformConfig/aiEvaluation). FAIL-CLOSED everywhere: this is the doc
// the app, portal, enqueue and worker all check; missing/false = off. A
// reason is required to disable; both directions are confirmed.
export function AiEvaluationSwitchCard({
  initialFlag,
}: {
  initialFlag: AiEvaluationFlagView;
}) {
  const [flag, setFlag] = useState(initialFlag);
  const [pendingState, setPendingState] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  async function apply() {
    if (pendingState === null) return;
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/ai-evaluation", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          enabled: pendingState,
          reason: reason.trim() || undefined,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? "Failed to update");
      }
      setFlag(await res.json());
      toast.success(
        pendingState
          ? "AI evaluation platform switch ENABLED"
          : "AI evaluation paused platform-wide"
      );
      setPendingState(null);
      setReason("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to update");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          AI Comprehension Evaluation (platform)
          <Switch
            checked={flag.enabled}
            onCheckedChange={(next) => setPendingState(next)}
          />
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm text-muted-foreground">
          Master switch for the AI evaluation pipeline. OFF stops job
          creation immediately and queued work terminates without provider
          spend. Fails closed — a missing document also means off. Per-school
          entitlement is separate (school → Subscription tab).
        </p>
        <p className="text-xs text-muted-foreground">
          {flag.enabled ? "Enabled" : "Disabled"}
          {flag.updatedAt
            ? ` · last change ${new Date(flag.updatedAt).toLocaleString()}`
            : ""}
          {flag.updatedByEmail ? ` by ${flag.updatedByEmail}` : ""}
          {!flag.enabled && flag.reason ? ` · reason: ${flag.reason}` : ""}
        </p>
      </CardContent>

      <Dialog
        open={pendingState !== null}
        onOpenChange={(open) => {
          if (!open) setPendingState(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {pendingState
                ? "Enable AI evaluation platform-wide?"
                : "Pause AI evaluation platform-wide?"}
            </DialogTitle>
            <DialogDescription>
              {pendingState
                ? "New comprehension recordings at entitled schools will be " +
                  "queued and evaluated. Only flip this once the pilot " +
                  "privacy gates are cleared."
                : "Job creation stops immediately; queued jobs terminate " +
                  "without provider spend. Teacher surfaces hide."}
            </DialogDescription>
          </DialogHeader>
          {!pendingState && (
            <div className="space-y-1.5">
              <Label htmlFor="ai-flag-reason">Reason (required)</Label>
              <Textarea
                id="ai-flag-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                placeholder="Why is AI evaluation being paused?"
              />
            </div>
          )}
          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => setPendingState(null)}
              disabled={saving}
            >
              Cancel
            </Button>
            <Button
              onClick={apply}
              disabled={saving || (!pendingState && !reason.trim())}
              variant={pendingState ? "default" : "destructive"}
            >
              {saving ? "Applying…" : pendingState ? "Enable" : "Pause"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
