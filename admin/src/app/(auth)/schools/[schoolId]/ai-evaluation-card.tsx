"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Textarea } from "@/components/ui/textarea";

interface SchoolAiConfig {
  enabled: boolean;
  capPerDay: number;
  plan: string;
  notes: string;
  termsVersionAccepted: string;
  updatedAt: string | null;
  updatedByEmail?: string;
  usageMonth?: string;
  usage?: Record<string, number> | null;
}

// Per-school AI comprehension-evaluation entitlement (Subscription tab).
// The entitlement lives on the school doc (client-visible, fail-closed);
// capPerDay/plan/notes live in deny-all adminMeta — never teacher-visible.
// Every save recomputes the derived global daily cap server-side.
export function AiEvaluationCard({
  schoolId,
  studentCount,
  initialConfig,
}: {
  schoolId: string;
  studentCount: number;
  initialConfig: SchoolAiConfig;
}) {
  const [config, setConfig] = useState<SchoolAiConfig>(initialConfig);
  const [saving, setSaving] = useState(false);
  const [enabled, setEnabled] = useState(initialConfig.enabled);
  const [capPerDay, setCapPerDay] = useState(initialConfig.capPerDay);
  const [plan, setPlan] = useState(initialConfig.plan);
  const [notes, setNotes] = useState(initialConfig.notes);
  const [terms, setTerms] = useState(initialConfig.termsVersionAccepted);

  const suggestedCap = Math.max(1, Math.ceil(studentCount * 1.5));

  async function save() {
    setSaving(true);
    try {
      const res = await fetch(`/api/schools/${schoolId}/ai-evaluation`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          enabled,
          capPerDay,
          plan,
          notes,
          termsVersionAccepted: terms,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? "Failed to save");
      }
      const updated: SchoolAiConfig = await res.json();
      setConfig(updated);
      setEnabled(updated.enabled);
      setCapPerDay(updated.capPerDay);
      setPlan(updated.plan);
      setNotes(updated.notes);
      setTerms(updated.termsVersionAccepted);
      toast.success("AI evaluation settings saved");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  }

  const usage = config?.usage;
  const estCost =
    usage && typeof usage.estCostUsdMillis === "number"
      ? (usage.estCostUsdMillis / 1000).toFixed(2)
      : null;

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          AI Comprehension Evaluation
          <Switch
            checked={enabled}
            onCheckedChange={setEnabled}
            disabled={saving}
          />
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Paid add-on, switched per commercial agreement. Fails closed: the
          school sees nothing until this is enabled AND the platform switch is
          on. Do not enable before the school&apos;s privacy notice and
          agreement are in place.
        </p>
        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-1">
            <Label htmlFor="ai-cap">Daily evaluation cap</Label>
            <Input
              id="ai-cap"
              type="number"
              min={0}
              value={capPerDay}
              onChange={(e) => setCapPerDay(Number(e.target.value))}
            />
            <p className="text-xs text-muted-foreground">
              Suggested: {suggestedCap} (students × 1.5). Hard COGS stop.
            </p>
          </div>
          <div className="space-y-1">
            <Label htmlFor="ai-plan">Plan label</Label>
            <Input
              id="ai-plan"
              value={plan}
              onChange={(e) => setPlan(e.target.value)}
              placeholder="e.g. Pilot 2026 T3"
            />
          </div>
        </div>
        <div className="space-y-1">
          <Label htmlFor="ai-terms">Terms version accepted</Label>
          <Input
            id="ai-terms"
            value={terms}
            onChange={(e) => setTerms(e.target.value)}
            placeholder="e.g. ai-eval-terms-v1 (required to enable)"
          />
        </div>
        <div className="space-y-1">
          <Label htmlFor="ai-notes">Internal notes</Label>
          <Textarea
            id="ai-notes"
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            rows={2}
          />
        </div>
        {config?.usageMonth && (
          <p className="text-xs text-muted-foreground">
            {config.usageMonth}: {usage?.evaluated ?? 0} evaluations
            {estCost ? ` · ~US$${estCost} est. COGS` : ""}
            {typeof usage?.sttSeconds === "number"
              ? ` · ${Math.round(usage.sttSeconds / 60)} STT min`
              : ""}
          </p>
        )}
        <div className="flex items-center justify-between">
          <p className="text-xs text-muted-foreground">
            {config?.updatedAt
              ? `Last change ${new Date(config.updatedAt).toLocaleString()}` +
                (config.updatedByEmail ? ` by ${config.updatedByEmail}` : "")
              : ""}
          </p>
          <Button onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}
