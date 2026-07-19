"use client";

import { useCallback, useEffect, useState } from "react";
import { RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { DemoFeatureControls } from "@/components/demo/demo-feature-controls";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { DemoControlValues } from "@/lib/demo/control-model";

interface DemoSettingsResponse {
  controls: DemoControlValues;
  credentialActive: boolean;
}

interface ReseedStatus {
  state: string;
  phase?: string | null;
  docsWritten?: number;
  error?: string | null;
  finishedAtISO?: string | null;
}

export function SchoolDemoControlsTab() {
  const [settings, setSettings] = useState<DemoSettingsResponse | null>(null);
  const [status, setStatus] = useState<ReseedStatus>({ state: "never" });
  const [refreshing, setRefreshing] = useState(false);
  const [confirmRefresh, setConfirmRefresh] = useState(false);

  const load = useCallback(async () => {
    const [settingsResponse, statusResponse] = await Promise.all([
      fetch("/api/demo/settings", { cache: "no-store" }),
      fetch("/api/demo/reseed", { cache: "no-store" }),
    ]);
    if (!settingsResponse.ok || !statusResponse.ok) {
      throw new Error("Could not load demo controls");
    }
    setSettings((await settingsResponse.json()) as DemoSettingsResponse);
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
      setStatus((await response.json()) as ReseedStatus);
    }, 1500);
    return () => window.clearInterval(id);
  }, [refreshing]);

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

  if (!settings) {
    return <p className="text-sm text-muted-foreground">Loading demo controls…</p>;
  }

  return (
    <div className="space-y-4">
      <DemoFeatureControls
        key={JSON.stringify(settings.controls)}
        initialControls={settings.controls}
        active={settings.credentialActive}
        patchEndpoint="/api/demo/settings"
      />

      <Card>
        <CardHeader>
          <CardTitle>Refresh demo data</CardTitle>
          <CardDescription>
            Replaces temporary demo activity with fresh relative dates. The
            daily password state is preserved.
          </CardDescription>
        </CardHeader>
        <CardContent className="flex items-center justify-between gap-4">
          <div className="text-sm">
            <p>
              Status: <strong>{status.state}</strong>
              {status.phase ? ` · ${status.phase}` : ""}
            </p>
            {status.error && <p className="text-destructive">{status.error}</p>}
          </div>
          <Button onClick={() => setConfirmRefresh(true)} disabled={refreshing}>
            <RefreshCw className={refreshing ? "animate-spin" : ""} />
            {refreshing ? "Refreshing…" : "Refresh demo data"}
          </Button>
        </CardContent>
      </Card>

      <ConfirmDialog
        open={confirmRefresh}
        onOpenChange={setConfirmRefresh}
        title="Refresh the demo school?"
        description="This permanently removes today's temporary demo changes and rebuilds the isolated demo tenant. It does not alter the active daily password."
        confirmLabel="Refresh demo"
        variant="destructive"
        onConfirm={refresh}
        loading={refreshing}
      />
    </div>
  );
}
