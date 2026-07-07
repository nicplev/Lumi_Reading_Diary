"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import type { OnboardingDetail } from "@/lib/firestore/onboarding";

// ISO → the value shape the native input expects (local wall-clock slice).
function toInput(iso: string | undefined, withTime: boolean): string {
  if (!iso) return "";
  return withTime ? iso.slice(0, 16) : iso.slice(0, 10);
}

interface FollowUpPanelProps {
  onboarding: OnboardingDetail;
}

export function FollowUpPanel({ onboarding }: FollowUpPanelProps) {
  const router = useRouter();
  const meta = (onboarding.metadata ?? {}) as Record<string, unknown>;

  const [demoAt, setDemoAt] = useState(
    toInput(onboarding.demoScheduledAt, true)
  );
  const [nextStepAt, setNextStepAt] = useState(
    toInput(typeof meta.nextStepAt === "string" ? meta.nextStepAt : undefined, false)
  );
  const [nextStepNote, setNextStepNote] = useState(
    typeof meta.nextStepNote === "string" ? meta.nextStepNote : ""
  );
  const [notes, setNotes] = useState(
    typeof meta.notes === "string" ? meta.notes : ""
  );
  const [loading, setLoading] = useState(false);

  const save = async () => {
    setLoading(true);
    try {
      const res = await fetch(`/api/onboarding/${onboarding.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "updateDetails",
          demoScheduledAt: demoAt ? new Date(demoAt).toISOString() : "",
          nextStepAt: nextStepAt ? new Date(nextStepAt).toISOString() : "",
          nextStepNote,
          notes,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Save failed");
      toast.success("Follow-up saved");
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Follow-up</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="grid gap-3 md:grid-cols-2">
          <div className="space-y-2">
            <Label>Demo scheduled</Label>
            <Input
              type="datetime-local"
              value={demoAt}
              onChange={(e) => setDemoAt(e.target.value)}
            />
          </div>
          <div className="space-y-2">
            <Label>Next step by</Label>
            <Input
              type="date"
              value={nextStepAt}
              onChange={(e) => setNextStepAt(e.target.value)}
            />
          </div>
        </div>
        <div className="space-y-2">
          <Label>Next step</Label>
          <Input
            value={nextStepNote}
            onChange={(e) => setNextStepNote(e.target.value)}
            placeholder="e.g. send recap + pricing band, book trial kickoff"
          />
        </div>
        <div className="space-y-2">
          <Label>Notes</Label>
          <Textarea
            rows={3}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Running notes — what landed, objections, recap sent…"
          />
        </div>
        <Button onClick={save} disabled={loading}>
          {loading ? "Saving…" : "Save follow-up"}
        </Button>
      </CardContent>
    </Card>
  );
}
