"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { BillingEntity } from "@lumi/types";

export function BillingSettingsForm({ entity }: { entity: BillingEntity }) {
  const router = useRouter();
  const [saving, setSaving] = useState(false);
  const [f, setF] = useState({
    legalName: entity.legalName ?? "",
    abn: entity.abn ?? "",
    address: entity.address ?? "",
    email: entity.email ?? "",
    gstRegistered: entity.gstRegistered ?? false,
    gstRate: entity.gstRate ?? 0.1,
    paymentDetails: entity.paymentDetails ?? "",
    pricePerStudent: entity.pricePerStudent,
    paymentTermsDays: entity.paymentTermsDays ?? 30,
  });

  async function save() {
    if (!f.legalName.trim()) return toast.error("Legal name is required.");
    setSaving(true);
    try {
      const res = await fetch("/api/billing-entity", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          legalName: f.legalName,
          abn: f.abn,
          address: f.address,
          email: f.email,
          gstRegistered: f.gstRegistered,
          gstRate: f.gstRate,
          paymentDetails: f.paymentDetails,
          pricePerStudent:
            typeof f.pricePerStudent === "number" ? f.pricePerStudent : undefined,
          paymentTermsDays: f.paymentTermsDays,
        }),
      });
      if (!res.ok) throw new Error((await res.json()).error || "Failed");
      toast.success("Billing details saved");
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to save");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card className="mt-4 max-w-2xl">
      <CardHeader>
        <CardTitle>Lumi invoicing entity</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <Label>Legal / trading name</Label>
          <Input value={f.legalName} onChange={(e) => setF({ ...f, legalName: e.target.value })} />
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>ABN</Label>
            <Input value={f.abn} onChange={(e) => setF({ ...f, abn: e.target.value })} />
          </div>
          <div className="space-y-2">
            <Label>Billing email</Label>
            <Input type="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} />
          </div>
        </div>
        <div className="space-y-2">
          <Label>Registered address</Label>
          <Textarea rows={2} value={f.address} onChange={(e) => setF({ ...f, address: e.target.value })} />
        </div>
        <div className="flex items-center gap-3">
          <Switch checked={f.gstRegistered} onCheckedChange={(v) => setF({ ...f, gstRegistered: v })} />
          <Label className="!m-0">Registered for GST (invoices default to 10% and are titled Tax Invoice)</Label>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label>Default price per student (AUD)</Label>
            <Input
              type="number"
              step="0.01"
              value={f.pricePerStudent ?? ""}
              onChange={(e) =>
                setF({ ...f, pricePerStudent: e.target.value === "" ? undefined : Number(e.target.value) })
              }
            />
          </div>
          <div className="space-y-2">
            <Label>Payment terms (days)</Label>
            <Input
              type="number"
              value={f.paymentTermsDays}
              onChange={(e) => setF({ ...f, paymentTermsDays: Number(e.target.value) })}
            />
          </div>
        </div>
        <div className="space-y-2">
          <Label>Payment details (bank / BSB / account, shown on invoices)</Label>
          <Textarea rows={3} value={f.paymentDetails} onChange={(e) => setF({ ...f, paymentDetails: e.target.value })} />
        </div>
        <Button onClick={save} disabled={saving}>
          {saving ? "Saving…" : "Save billing details"}
        </Button>
      </CardContent>
    </Card>
  );
}
