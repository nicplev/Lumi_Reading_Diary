"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { INVOICE_STATUS_VALUES, type InvoiceStatus } from "@lumi/types";
import type { InvoiceRow } from "@/lib/firestore/invoices";
import type { InvoiceDocData } from "@/components/invoicing/invoice-document";

function money(n: number, currency: string) {
  try {
    return new Intl.NumberFormat("en-AU", { style: "currency", currency }).format(n);
  } catch {
    return `$${n.toFixed(2)}`;
  }
}
function fmtDate(iso?: string) {
  if (!iso) return "—";
  const d = new Date(iso);
  return isNaN(d.getTime())
    ? "—"
    : d.toLocaleDateString("en-AU", { day: "numeric", month: "short", year: "numeric" });
}
const statusVariant: Record<InvoiceStatus, "default" | "secondary" | "destructive" | "outline"> = {
  draft: "outline",
  issued: "secondary",
  paid: "default",
  void: "destructive",
};

export function InvoiceRegister({ invoices }: { invoices: InvoiceRow[] }) {
  const router = useRouter();
  const [filter, setFilter] = useState<"all" | InvoiceStatus>("all");
  const [busyId, setBusyId] = useState<string | null>(null);

  const rows = useMemo(
    () => (filter === "all" ? invoices : invoices.filter((i) => i.status === filter)),
    [invoices, filter]
  );

  async function downloadPdf(inv: InvoiceRow) {
    setBusyId(inv.id);
    try {
      const [{ downloadInvoicePdf, imageToDataUrl }] = await Promise.all([
        import("@/components/invoicing/invoice-document"),
      ]);
      const logo = await imageToDataUrl("/lumi-invoice-logo.png");
      await downloadInvoicePdf(inv as unknown as InvoiceDocData, logo);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to generate PDF");
    } finally {
      setBusyId(null);
    }
  }

  async function emailInvoice(inv: InvoiceRow) {
    const to = inv.billTo?.email?.trim();
    if (!to) {
      toast.error("This invoice has no recipient email — add one to email it.");
      return;
    }
    setBusyId(inv.id);
    try {
      const { invoicePdfBlob, imageToDataUrl } = await import(
        "@/components/invoicing/invoice-document"
      );
      const logo = await imageToDataUrl("/lumi-invoice-logo.png");
      const blob = await invoicePdfBlob(inv as unknown as InvoiceDocData, logo);
      const dataUrl: string = await new Promise((resolve, reject) => {
        const r = new FileReader();
        r.onloadend = () => resolve(r.result as string);
        r.onerror = reject;
        r.readAsDataURL(blob);
      });
      const pdfBase64 = dataUrl.split(",")[1];
      const res = await fetch(`/api/invoicing/${inv.id}/email`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          to,
          pdfBase64,
          filename: `${inv.invoiceNumber || "invoice"}.pdf`,
        }),
      });
      if (!res.ok) throw new Error((await res.json()).error || "Failed");
      toast.success(`Invoice queued to ${to}`);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to email invoice");
    } finally {
      setBusyId(null);
    }
  }

  async function setStatus(inv: InvoiceRow, status: InvoiceStatus) {
    setBusyId(inv.id);
    try {
      const res = await fetch(`/api/invoicing/${inv.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      if (!res.ok) throw new Error((await res.json()).error || "Failed");
      toast.success(`Marked ${status}`);
      router.refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Failed to update");
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <Select value={filter} onValueChange={(v) => setFilter(v as typeof filter)}>
          <SelectTrigger className="w-44">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            {INVOICE_STATUS_VALUES.map((s) => (
              <SelectItem key={s} value={s}>
                {s[0].toUpperCase() + s.slice(1)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <span className="text-sm text-muted-foreground">{rows.length} invoice(s)</span>
      </div>

      <div className="rounded-md border">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Invoice #</TableHead>
              <TableHead>Bill to</TableHead>
              <TableHead>Issue date</TableHead>
              <TableHead className="text-right">Total</TableHead>
              <TableHead>Status</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-muted-foreground py-8">
                  No invoices yet.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((inv) => (
                <TableRow key={inv.id}>
                  <TableCell className="font-medium">{inv.invoiceNumber || "Draft"}</TableCell>
                  <TableCell>{inv.billTo?.name || "—"}</TableCell>
                  <TableCell>{fmtDate(inv.issueDate)}</TableCell>
                  <TableCell className="text-right">{money(inv.total, inv.currency)}</TableCell>
                  <TableCell>
                    <Badge variant={statusVariant[inv.status]}>{inv.status}</Badge>
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex justify-end gap-1.5">
                      <Button size="sm" variant="outline" disabled={busyId === inv.id} onClick={() => downloadPdf(inv)}>
                        PDF
                      </Button>
                      <Button size="sm" variant="outline" disabled={busyId === inv.id} onClick={() => emailInvoice(inv)}>
                        Email
                      </Button>
                      {inv.status !== "paid" && (
                        <Button size="sm" variant="outline" disabled={busyId === inv.id} onClick={() => setStatus(inv, "paid")}>
                          Mark paid
                        </Button>
                      )}
                      {inv.status !== "void" && (
                        <Button size="sm" variant="ghost" disabled={busyId === inv.id} onClick={() => setStatus(inv, "void")}>
                          Void
                        </Button>
                      )}
                    </div>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}
