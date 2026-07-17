"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCw, Plus, Trash2, MicOff } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";

interface PresetCategory { id: string; name: string; chips: string[] }
interface DemoSettings {
  messagingEnabled: boolean;
  parentCommentsEnabled: boolean;
  freeTextEnabled: boolean;
  quickLoggingEnabled: boolean;
  customPresets: PresetCategory[];
  comprehensionRecordingEnabled: false;
  comprehensionMode: "playback-only";
}
interface ReseedStatus {
  state: string;
  phase?: string | null;
  docsWritten?: number;
  error?: string | null;
  finishedAtISO?: string | null;
}

export function SchoolDemoControlsTab() {
  const [settings, setSettings] = useState<DemoSettings | null>(null);
  const [status, setStatus] = useState<ReseedStatus>({ state: "never" });
  const [saving, setSaving] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [confirmRefresh, setConfirmRefresh] = useState(false);
  const [newCategory, setNewCategory] = useState("");
  const [newChips, setNewChips] = useState<Record<string, string>>({});

  const load = useCallback(async () => {
    const [settingsResponse, statusResponse] = await Promise.all([
      fetch("/api/demo/settings", { cache: "no-store" }),
      fetch("/api/demo/reseed", { cache: "no-store" }),
    ]);
    if (!settingsResponse.ok || !statusResponse.ok) throw new Error("Could not load demo controls");
    setSettings((await settingsResponse.json()) as DemoSettings);
    setStatus((await statusResponse.json()) as ReseedStatus);
  }, []);

  useEffect(() => {
    const initialLoad = window.setTimeout(() => {
      load().catch((error) => toast.error(error.message));
    }, 0);
    const onFocus = () => load().catch(() => undefined);
    window.addEventListener("focus", onFocus);
    return () => {
      window.clearTimeout(initialLoad);
      window.removeEventListener("focus", onFocus);
    };
  }, [load]);

  useEffect(() => {
    if (!refreshing) return;
    const id = window.setInterval(async () => {
      const response = await fetch("/api/demo/reseed", { cache: "no-store" });
      if (!response.ok) return;
      const next = (await response.json()) as ReseedStatus;
      setStatus(next);
    }, 1500);
    return () => window.clearInterval(id);
  }, [refreshing]);

  const patch = async (value: Record<string, unknown>) => {
    setSaving(true);
    try {
      const response = await fetch("/api/demo/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(value),
      });
      const json = await response.json();
      if (!response.ok) throw new Error(json.error ?? "Update failed");
      setSettings(json as DemoSettings);
      toast.success("Demo setting updated");
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Update failed");
      await load().catch(() => undefined);
    } finally {
      setSaving(false);
    }
  };

  const refresh = async () => {
    setConfirmRefresh(false);
    setRefreshing(true);
    setStatus({ state: "running", phase: "starting" });
    try {
      const response = await fetch("/api/demo/reseed", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ confirm: "REFRESH DEMO" }),
      });
      const json = await response.json();
      if (!response.ok) throw new Error(json.error ?? "Refresh failed");
      toast.success(`Demo refreshed (${json.docsWritten} documents)`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Refresh failed");
    } finally {
      setRefreshing(false);
      await load().catch(() => undefined);
    }
  };

  const addCategory = () => {
    if (!settings || !newCategory.trim() || settings.customPresets.length >= 10) return;
    patch({
      customPresets: [...settings.customPresets, {
        id: crypto.randomUUID(), name: newCategory.trim(), chips: [],
      }],
    });
    setNewCategory("");
  };

  const removeCategory = (id: string) => {
    if (!settings) return;
    patch({ customPresets: settings.customPresets.filter((item) => item.id !== id) });
  };

  const addChip = (id: string) => {
    if (!settings) return;
    const text = (newChips[id] ?? "").trim();
    if (!text || text.length > 100) return;
    const customPresets = settings.customPresets.map((item) =>
      item.id === id && item.chips.length < 20 && !item.chips.includes(text)
        ? { ...item, chips: [...item.chips, text] }
        : item
    );
    patch({ customPresets });
    setNewChips((current) => ({ ...current, [id]: "" }));
  };

  const removeChip = (id: string, chip: string) => {
    if (!settings) return;
    patch({
      customPresets: settings.customPresets.map((item) =>
        item.id === id ? { ...item, chips: item.chips.filter((value) => value !== chip) } : item
      ),
    });
  };

  if (!settings) return <p className="text-sm text-muted-foreground">Loading demo controls…</p>;

  const toggles: Array<{ key: keyof DemoSettings; label: string; description: string }> = [
    { key: "messagingEnabled", label: "Messaging", description: "Show the school-local parent and teacher messaging experience." },
    { key: "parentCommentsEnabled", label: "Parent comments", description: "Allow comments while families log reading." },
    { key: "freeTextEnabled", label: "Free-text comments", description: "Allow typed comments in addition to preset chips." },
    { key: "quickLoggingEnabled", label: "Quick logging", description: "Show the faster reading-log path in the demo app." },
  ];

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Live demo features</CardTitle>
          <CardDescription>These switches update only the isolated demo school and stream to signed-in apps.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {toggles.map((item) => (
            <div key={item.key} className="flex items-center justify-between gap-6 border-b pb-4 last:border-0 last:pb-0">
              <div><p className="font-medium">{item.label}</p><p className="text-sm text-muted-foreground">{item.description}</p></div>
              <Switch
                checked={settings[item.key] as boolean}
                disabled={saving}
                onCheckedChange={(checked) => patch({ [item.key]: checked })}
              />
            </div>
          ))}
          <div className="flex items-center justify-between gap-6 rounded-lg border border-amber-300 bg-amber-50 p-3 text-amber-950">
            <div className="flex gap-3"><MicOff className="mt-0.5 h-5 w-5" /><div><p className="font-medium">Comprehension audio: playback only</p><p className="text-sm">Shared credentials cannot upload new recordings until a quota-enforced demo ingestion path exists.</p></div></div>
            <Switch checked={false} disabled aria-label="Comprehension audio upload disabled" />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Parent comment chips</CardTitle><CardDescription>Up to 10 categories and 20 chips per category.</CardDescription></CardHeader>
        <CardContent className="space-y-4">
          {settings.customPresets.map((category) => (
            <div key={category.id} className="rounded-lg border p-3">
              <div className="mb-3 flex items-center justify-between"><p className="font-medium">{category.name}</p><Button variant="ghost" size="icon-sm" onClick={() => removeCategory(category.id)} disabled={saving} aria-label={`Delete ${category.name}`}><Trash2 /></Button></div>
              <div className="mb-3 flex flex-wrap gap-2">
                {category.chips.map((chip) => <button key={chip} className="rounded-full border px-3 py-1 text-xs hover:bg-muted" onClick={() => removeChip(category.id, chip)} disabled={saving} title="Remove chip">{chip} ×</button>)}
              </div>
              <div className="flex gap-2"><Input maxLength={100} value={newChips[category.id] ?? ""} placeholder="Add a comment chip" onChange={(event) => setNewChips((current) => ({ ...current, [category.id]: event.target.value }))} /><Button variant="outline" onClick={() => addChip(category.id)} disabled={saving}><Plus /> Add</Button></div>
            </div>
          ))}
          <div className="flex gap-2"><Input maxLength={50} value={newCategory} placeholder="New category name" onChange={(event) => setNewCategory(event.target.value)} /><Button onClick={addCategory} disabled={saving || settings.customPresets.length >= 10}><Plus /> Add category</Button></div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle>Refresh demo data</CardTitle><CardDescription>Replaces temporary demo activity with fresh relative dates. The daily password state is preserved.</CardDescription></CardHeader>
        <CardContent className="flex items-center justify-between gap-4">
          <div className="text-sm"><p>Status: <strong>{status.state}</strong>{status.phase ? ` · ${status.phase}` : ""}</p>{status.error && <p className="text-destructive">{status.error}</p>}</div>
          <Button onClick={() => setConfirmRefresh(true)} disabled={refreshing}><RefreshCw className={refreshing ? "animate-spin" : ""} />{refreshing ? "Refreshing…" : "Refresh demo data"}</Button>
        </CardContent>
      </Card>
      <ConfirmDialog open={confirmRefresh} onOpenChange={setConfirmRefresh} title="Refresh the demo school?" description="This permanently removes today's temporary demo changes and rebuilds the isolated demo tenant. It does not alter the active daily password." confirmLabel="Refresh demo" variant="destructive" onConfirm={refresh} loading={refreshing} />
    </div>
  );
}
