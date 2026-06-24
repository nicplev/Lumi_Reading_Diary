"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import { tierForStudentCount } from "@lumi/types";
import type {
  SubscriptionStatus,
  SubscriptionTier,
} from "@lumi/types";
import type { SchoolSubscriptionRow } from "@/lib/firestore/school-subscriptions";

const STATUSES: SubscriptionStatus[] = [
  "paid",
  "unpaid",
  "comp",
  "trial",
  "grace",
  "cancelled",
];
const TIERS: SubscriptionTier[] = ["S", "M", "L", "XL"];

// paid/comp/trial/grace grant access; unpaid/cancelled suspend.
function statusBadge(status: SubscriptionStatus) {
  const active = ["paid", "comp", "trial", "grace"].includes(status);
  return <StatusBadge status={active ? "active" : "suspended"} />;
}

interface Props {
  schoolId: string;
  studentCount: number;
  currentAcademicYear: number;
  initialSubscriptions: SchoolSubscriptionRow[];
}

export function SchoolSubscriptionTab({
  schoolId,
  studentCount,
  currentAcademicYear,
  initialSubscriptions,
}: Props) {
  const router = useRouter();
  const [rows, setRows] = useState<SchoolSubscriptionRow[]>(
    initialSubscriptions
  );
  const existing = rows.find((r) => r.academicYear === currentAcademicYear);
  const suggestedTier = tierForStudentCount(studentCount);

  const [year, setYear] = useState<number>(currentAcademicYear);
  const [status, setStatus] = useState<SubscriptionStatus>(
    existing?.status ?? "comp"
  );
  const [tier, setTier] = useState<SubscriptionTier>(
    existing?.tier ?? suggestedTier
  );
  const [amount, setAmount] = useState<string>(
    existing?.amount != null ? String(existing.amount) : ""
  );
  const [invoiceRef, setInvoiceRef] = useState<string>(
    existing?.invoiceRef ?? ""
  );
  const [notes, setNotes] = useState<string>(existing?.notes ?? "");
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      const res = await fetch("/api/school-subscriptions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          schoolId,
          academicYear: year,
          status,
          tier,
          amount: amount === "" ? undefined : Number(amount),
          invoiceRef: invoiceRef || undefined,
          notes: notes || undefined,
        }),
      });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? "Save failed");
      }
      toast.success(`Subscription saved for ${year}`);
      // Refresh the list from the server.
      const listed = await fetch(
        `/api/school-subscriptions?schoolId=${schoolId}`
      ).then((r) => r.json());
      setRows(listed.subscriptions ?? []);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>
            Platform Subscription — {currentAcademicYear} (current year)
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground">
            Lumi → school annual platform fee, invoiced manually. This status
            governs the whole school&apos;s access: <strong>paid / comp / trial
            / grace</strong> keep access on; <strong>unpaid / cancelled</strong>{" "}
            suspend the school and every family. Suggested tier for{" "}
            {studentCount} students: <strong>{suggestedTier}</strong>.
          </p>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-1.5">
              <Label htmlFor="sub-year">Academic year</Label>
              <Input
                id="sub-year"
                type="number"
                value={year}
                onChange={(e) => setYear(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label>Status</Label>
              <Select
                value={status}
                onValueChange={(v) => setStatus(v as SubscriptionStatus)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {STATUSES.map((s) => (
                    <SelectItem key={s} value={s}>
                      {s}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Tier</Label>
              <Select
                value={tier}
                onValueChange={(v) => setTier(v as SubscriptionTier)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {TIERS.map((t) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="sub-amount">Amount (AUD)</Label>
              <Input
                id="sub-amount"
                type="number"
                value={amount}
                placeholder="e.g. 199"
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="sub-invoice">Invoice ref</Label>
              <Input
                id="sub-invoice"
                value={invoiceRef}
                placeholder="INV-..."
                onChange={(e) => setInvoiceRef(e.target.value)}
              />
            </div>
            <div className="space-y-1.5 sm:col-span-2">
              <Label htmlFor="sub-notes">Notes</Label>
              <Textarea
                id="sub-notes"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
              />
            </div>
          </div>
          <Button onClick={save} disabled={saving}>
            {saving ? "Saving…" : "Save subscription"}
          </Button>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>History</CardTitle>
        </CardHeader>
        <CardContent>
          {rows.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No subscription rows yet.
            </p>
          ) : (
            <div className="space-y-2">
              {rows.map((r) => (
                <div
                  key={r.id}
                  className="flex items-center justify-between border-b py-2 text-sm last:border-0"
                >
                  <span className="font-medium">{r.academicYear}</span>
                  <span className="flex items-center gap-3">
                    {statusBadge(r.status)}
                    <span className="text-muted-foreground">{r.status}</span>
                    {r.tier && <span>Tier {r.tier}</span>}
                    {r.amount != null && <span>${r.amount}</span>}
                    {r.invoiceRef && (
                      <span className="text-muted-foreground">
                        {r.invoiceRef}
                      </span>
                    )}
                    {r.paidAt && (
                      <span className="text-muted-foreground">
                        paid {formatDate(r.paidAt)}
                      </span>
                    )}
                  </span>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
