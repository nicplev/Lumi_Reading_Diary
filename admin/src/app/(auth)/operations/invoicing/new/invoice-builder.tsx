"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { BillingEntity } from "@lumi/types";
import type { InvoiceDocData } from "@/components/invoicing/invoice-document";

type SchoolOption = { id: string; name: string; studentCount: number };
type LineItem = { description: string; quantity: number; unitPrice: number };

function round2(n: number) {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}
function money(n: number, currency = "AUD") {
  try {
    return new Intl.NumberFormat("en-AU", { style: "currency", currency }).format(n);
  } catch {
    return `$${n.toFixed(2)}`;
  }
}
function todayISO() {
  return new Date().toISOString().slice(0, 10);
}
function addDaysISO(baseISO: string, days: number) {
  const d = new Date(baseISO);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export function InvoiceBuilder({
  schools,
  entity,
  currentYear,
  preselectSchoolId,
  preselectYear,
}: {
  schools: SchoolOption[];
  entity: BillingEntity;
  currentYear: number;
  preselectSchoolId?: string;
  preselectYear?: number;
}) {
  const router = useRouter();
  const preschool = schools.find((s) => s.id === preselectSchoolId);

  const [schoolId, setSchoolId] = useState<string>(preselectSchoolId ?? "");
  const [academicYear] = useState<number>(preselectYear ?? currentYear);
  const [billTo, setBillTo] = useState({
    name: preschool?.name ?? "",
    contactPerson: "",
    email: "",
    address: "",
    abn: "",
  });
  const termsDays = entity.paymentTermsDays ?? 30;
  const [issueDate, setIssueDate] = useState(todayISO());
  const [dueDate, setDueDate] = useState(addDaysISO(todayISO(), termsDays));
  const [taxRate, setTaxRate] = useState<number>(entity.gstRegistered ? entity.gstRate : 0);
  const [notes, setNotes] = useState("");
  const [terms, setTerms] = useState("");
  const [saving, setSaving] = useState(false);
  const [downloading, setDownloading] = useState(false);

  const perStudentDefault = entity.pricePerStudent ?? 0;
  const [lineItems, setLineItems] = useState<LineItem[]>(
    preschool
      ? [
          {
            description: `Lumi reading platform — per student (${academicYear})`,
            quantity: preschool.studentCount,
            unitPrice: perStudentDefault,
          },
        ]
      : []
  );

  function onSelectSchool(id: string) {
    setSchoolId(id);
    const s = schools.find((x) => x.id === id);
    if (s) setBillTo((b) => ({ ...b, name: b.name || s.name }));
  }

  function addPerStudent() {
    const s = schools.find((x) => x.id === schoolId);
    setLineItems((li) => [
      ...li,
      {
        description: `Lumi reading platform — per student (${academicYear})`,
        quantity: s?.studentCount ?? 0,
        unitPrice: perStudentDefault,
      },
    ]);
  }
  function addServiceFee() {
    setLineItems((li) => [
      ...li,
      { description: "Service / admin fee", quantity: 1, unitPrice: 0 },
    ]);
  }
  function addCustom() {
    setLineItems((li) => [...li, { description: "", quantity: 1, unitPrice: 0 }]);
  }
  function updateItem(i: number, patch: Partial<LineItem>) {
    setLineItems((li) => li.map((it, idx) => (idx === i ? { ...it, ...patch } : it)));
  }
  function removeItem(i: number) {
    setLineItems((li) => li.filter((_, idx) => idx !== i));
  }

  const totals = useMemo(() => {
    const items = lineItems.map((it) => ({
      ...it,
      amount: round2(it.quantity * it.unitPrice),
    }));
    const subtotal = round2(items.reduce((s, it) => s + it.amount, 0));
    const taxAmount = round2(subtotal * taxRate);
    const total = round2(subtotal + taxAmount);
    return { items, subtotal, taxAmount, total };
  }, [lineItems, taxRate]);

  function buildDoc(): InvoiceDocData {
    return {
      invoiceNumber: "",
      issueDate,
      dueDate,
      billTo,
      from: {
        name: entity.legalName,
        email: entity.email,
        address: entity.address,
        abn: entity.abn,
        gstRegistered: entity.gstRegistered,
        gstRate: entity.gstRate,
        paymentDetails: entity.paymentDetails,
      },
      lineItems: totals.items,
      subtotal: totals.subtotal,
      taxRate,
      taxAmount: totals.taxAmount,
      total: totals.total,
      currency: "AUD",
      notes: notes || undefined,
      terms: terms || undefined,
    };
  }

  function validate(): string | null {
    if (!billTo.name.trim()) return "Recipient name is required.";
    if (lineItems.length === 0) return "Add at least one line item.";
    if (lineItems.some((it) => !it.description.trim())) return "Every line item needs a description.";
    return null;
  }

  async function onDownload() {
    const err = validate();
    if (err) return toast.error(err);
    setDownloading(true);
    try {
      const { downloadInvoicePdf, imageToDataUrl } = await import(
        "@/components/invoicing/invoice-document"
      );
      const logo = await imageToDataUrl("/lumi-invoice-logo.png");
      await downloadInvoicePdf(buildDoc(), logo);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to generate PDF");
    } finally {
      setDownloading(false);
    }
  }

  async function onSave(status: "draft" | "issued") {
    const err = validate();
    if (err) return toast.error(err);
    setSaving(true);
    try {
      const res = await fetch("/api/invoicing", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          schoolId: schoolId || undefined,
          academicYear: schoolId ? academicYear : undefined,
          issueDate,
          dueDate: dueDate || undefined,
          billTo,
          lineItems: lineItems.map((it) => ({
            description: it.description,
            quantity: it.quantity,
            unitPrice: it.unitPrice,
          })),
          taxRate,
          currency: "AUD",
          notes: notes || undefined,
          terms: terms || undefined,
          status,
        }),
      });
      if (!res.ok) throw new Error((await res.json()).error || "Failed to save");
      const { invoice } = await res.json();
      toast.success(`Invoice ${invoice.invoiceNumber} saved`);
      router.push("/operations/invoicing");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to save invoice");
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="mt-4 grid gap-4 lg:grid-cols-3">
      <div className="lg:col-span-2 space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Recipient</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label>Link to school (optional)</Label>
                <Select value={schoolId} onValueChange={(v) => v && onSelectSchool(v)}>
                  <SelectTrigger>
                    <SelectValue placeholder="No school — custom invoice" />
                  </SelectTrigger>
                  <SelectContent>
                    {schools.map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.name} ({s.studentCount})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <Label>Bill to (name)</Label>
                <Input
                  value={billTo.name}
                  onChange={(e) => setBillTo({ ...billTo, name: e.target.value })}
                  placeholder="School office, KAKA Kids, …"
                />
              </div>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label>Attention / contact person</Label>
                <Input value={billTo.contactPerson} onChange={(e) => setBillTo({ ...billTo, contactPerson: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>Email</Label>
                <Input type="email" value={billTo.email} onChange={(e) => setBillTo({ ...billTo, email: e.target.value })} />
              </div>
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-2">
                <Label>Address</Label>
                <Textarea rows={2} value={billTo.address} onChange={(e) => setBillTo({ ...billTo, address: e.target.value })} />
              </div>
              <div className="space-y-2">
                <Label>ABN (optional)</Label>
                <Input value={billTo.abn} onChange={(e) => setBillTo({ ...billTo, abn: e.target.value })} />
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Line items</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {lineItems.map((it, i) => (
              <div key={i} className="grid grid-cols-12 gap-2 items-center">
                <Input
                  className="col-span-6"
                  placeholder="Description"
                  value={it.description}
                  onChange={(e) => updateItem(i, { description: e.target.value })}
                />
                <Input
                  className="col-span-2"
                  type="number"
                  placeholder="Qty"
                  value={it.quantity}
                  onChange={(e) => updateItem(i, { quantity: Number(e.target.value) })}
                />
                <Input
                  className="col-span-2"
                  type="number"
                  step="0.01"
                  placeholder="Unit $"
                  value={it.unitPrice}
                  onChange={(e) => updateItem(i, { unitPrice: Number(e.target.value) })}
                />
                <div className="col-span-1 text-right text-sm">
                  {money(round2(it.quantity * it.unitPrice))}
                </div>
                <Button className="col-span-1" size="sm" variant="ghost" onClick={() => removeItem(i)}>
                  ✕
                </Button>
              </div>
            ))}
            <div className="flex flex-wrap gap-2 pt-1">
              <Button size="sm" variant="outline" onClick={addPerStudent}>+ Per student</Button>
              <Button size="sm" variant="outline" onClick={addServiceFee}>+ Service/admin fee</Button>
              <Button size="sm" variant="outline" onClick={addCustom}>+ Custom line</Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Details</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-3">
              <div className="space-y-2">
                <Label>Issue date</Label>
                <Input type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>Due date</Label>
                <Input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
              </div>
              <div className="space-y-2">
                <Label>GST rate</Label>
                <Select value={String(taxRate)} onValueChange={(v) => setTaxRate(Number(v))}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="0.1">GST 10%</SelectItem>
                    <SelectItem value="0">No GST</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div className="space-y-2">
              <Label>Notes</Label>
              <Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} />
            </div>
            <div className="space-y-2">
              <Label>Terms</Label>
              <Textarea rows={2} value={terms} onChange={(e) => setTerms(e.target.value)} />
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Summary</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted-foreground">Subtotal</span>
              <span className="font-medium">{money(totals.subtotal)}</span>
            </div>
            {taxRate > 0 && (
              <div className="flex justify-between">
                <span className="text-muted-foreground">GST ({Math.round(taxRate * 100)}%)</span>
                <span className="font-medium">{money(totals.taxAmount)}</span>
              </div>
            )}
            <div className="flex justify-between border-t pt-2 text-base">
              <span className="font-semibold">Total</span>
              <span className="font-semibold">{money(totals.total)}</span>
            </div>
            <div className="pt-3 space-y-2">
              <Button className="w-full" variant="outline" disabled={downloading} onClick={onDownload}>
                {downloading ? "Generating…" : "Download PDF"}
              </Button>
              <Button className="w-full" disabled={saving} onClick={() => onSave("issued")}>
                {saving ? "Saving…" : "Save invoice"}
              </Button>
              <Button className="w-full" variant="ghost" disabled={saving} onClick={() => onSave("draft")}>
                Save as draft
              </Button>
            </div>
            <p className="text-xs text-muted-foreground pt-2">
              From: {entity.legalName}
              {entity.abn ? ` · ABN ${entity.abn}` : " · ABN not set"}
            </p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
