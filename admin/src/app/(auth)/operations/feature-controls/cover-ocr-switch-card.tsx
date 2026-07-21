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

export interface CoverOcrFlagView {
  enabled: boolean;
  configured: boolean;
  updatedAt: string | null;
  updatedByEmail?: string;
  reason?: string;
}

// Platform-wide book-cover OCR kill switch (platformConfig/coverOcr).
//
// FAILS OPEN, unlike the AI-evaluation card above it: a missing document or
// a read error both mean ON. The copy has to say so, because a card that
// rendered a never-written flag as a deliberate "Enabled" would misrepresent
// the state of the feature — hence the separate "defaulting to on" line.
export function CoverOcrSwitchCard({
  initialFlag,
}: {
  initialFlag: CoverOcrFlagView;
}) {
  const [flag, setFlag] = useState(initialFlag);
  const [pendingState, setPendingState] = useState<boolean | null>(null);
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);

  async function apply() {
    if (pendingState === null) return;
    setSaving(true);
    try {
      const res = await fetch("/api/platform-config/cover-ocr", {
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
          ? "Cover OCR ENABLED platform-wide"
          : "Cover OCR paused platform-wide"
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
          Book Cover OCR (platform)
          <Switch
            checked={flag.enabled}
            onCheckedChange={(next) => setPendingState(next)}
          />
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <p className="text-sm text-muted-foreground">
          Reads a scanned book cover to pre-fill the title and author when a
          teacher adds a book no catalog knows. OFF means teachers type both
          fields by hand, exactly as before — contributing a book is never
          blocked. Takes effect within 60s; no deploy and no app release
          needed.
        </p>
        <p className="text-sm text-muted-foreground">
          Unlike AI evaluation above, this switch{" "}
          <strong>fails open</strong>: only an explicit OFF disables it. Book
          covers carry no student data, so no per-school entitlement applies.
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
                ? "Enable cover OCR platform-wide?"
                : "Pause cover OCR platform-wide?"}
            </DialogTitle>
            <DialogDescription>
              {pendingState
                ? "New books scanned into the Lumi library will have their " +
                  "title and author pre-filled from the cover photo for the " +
                  "teacher to confirm."
                : "Title and author fields stay empty and teachers type them " +
                  "by hand. No provider spend. Books can still be added " +
                  "normally — nothing is blocked."}
            </DialogDescription>
          </DialogHeader>
          {!pendingState && (
            <div className="space-y-1.5">
              <Label htmlFor="cover-ocr-reason">Reason (required)</Label>
              <Textarea
                id="cover-ocr-reason"
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                placeholder="Why is cover OCR being paused?"
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
