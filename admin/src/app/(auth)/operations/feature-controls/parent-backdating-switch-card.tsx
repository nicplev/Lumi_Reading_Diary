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
import type { ParentBackdatingFlag } from "@lumi/server-ops";

// Parent Yesterday-backdating switch (platformConfig/parentBackdating).
//
// Decision D1 of the parent-logging redesign: parents may record a session
// for Yesterday (never further back) in the detailed logging flow. It ships
// ON for the first round of school testing; this card is the no-release
// off-switch Nic conditioned the approval on, to be flipped on evidence
// (the `backdated_session` analytics counter).
//
// FAILS OPEN like cover OCR: a missing document means ON, so the copy must
// distinguish "on by default" from "on because someone chose it".
export function ParentBackdatingSwitchCard({
  initialFlag,
}: {
  initialFlag: ParentBackdatingFlag;
}) {
  const [flag, setFlag] = useState(initialFlag);
  const [pendingState, setPendingState] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  async function apply() {
    if (pendingState === null) return;
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/parent-backdating", {
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
          ? "Parent backdating ENABLED platform-wide"
          : "Parent backdating turned OFF platform-wide"
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
          Parent backdating — Yesterday (platform)
          <Switch
            checked={flag.enabled}
            onCheckedChange={(next) => setPendingState(next)}
            aria-label="Toggle parent Yesterday backdating platform-wide"
          />
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm text-muted-foreground">
          Lets a parent record a reading session for <strong>yesterday</strong>{" "}
          (school time, never further back) in the detailed logging flow. OFF
          hides the Today/Yesterday choice everywhere and every session is
          recorded as today — the pre-redesign behaviour. Takes effect within
          ~5 minutes per app (client cache); no deploy and no app release
          needed.
        </p>
        <p className="text-sm text-muted-foreground">
          Like cover OCR, this switch <strong>fails open</strong>: only an
          explicit OFF disables it. Watch the{" "}
          <code className="text-xs">backdated_session</code> analytics counter
          to judge whether the one-day window is being used as intended before
          deciding.
        </p>
        {!flag.configured && flag.enabled ? (
          <p className="text-xs text-amber-600 dark:text-amber-500">
            Defaulting to on — no configuration document exists yet. Toggling
            this switch writes one.
          </p>
        ) : (
          <p className="text-xs text-muted-foreground">
            {flag.enabled ? "Enabled" : "Disabled"}
            {flag.updatedAt
              ? ` · last change ${new Date(flag.updatedAt).toLocaleString()}`
              : ""}
            {flag.updatedByEmail ? ` by ${flag.updatedByEmail}` : ""}
            {!flag.enabled && flag.reason ? ` · reason: ${flag.reason}` : ""}
          </p>
        )}
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
                ? "Enable parent backdating platform-wide?"
                : "Turn off parent backdating platform-wide?"}
            </DialogTitle>
            <DialogDescription>
              {pendingState
                ? "Parents in every school get the Today/Yesterday choice " +
                  "back in the detailed logging flow. Yesterday remains the " +
                  "hard limit — nothing older can ever be recorded."
                : "The Today/Yesterday choice disappears from the detailed " +
                  "logging flow in every school within ~5 minutes; every " +
                  "session is recorded as today. Sessions already saved for " +
                  "yesterday keep their recorded day."}
            </DialogDescription>
          </DialogHeader>
          {!pendingState && (
            <div className="space-y-1.5">
              <Label htmlFor="parent-backdating-reason">
                Reason (required)
              </Label>
              <Textarea
                id="parent-backdating-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                placeholder="e.g. Friday batch-logging pattern showing up in the beta data"
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
              {saving ? "Applying…" : pendingState ? "Enable" : "Turn off"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Card>
  );
}
