"use client";

// Loaded only via dynamic import (on the builder page / download click), so
// @react-pdf stays out of the main admin bundle and never runs during SSR/build.
import {
  Document,
  Page,
  Text,
  View,
  Image,
  StyleSheet,
  pdf,
} from "@react-pdf/renderer";

// Lumi palette (kept in sync with school-admin-web/src/app/globals.css).
// @react-pdf can't read CSS vars, so brand colours live here as literals.
const C = {
  red: "#EC4544",
  yellow: "#FFCB05",
  green: "#51BA65",
  cream: "#F7F5F0",
  paper: "#FFFFFF",
  ink: "#1A1A1A",
  muted: "#6B6B6B",
  rule: "#E5E2DC",
  white: "#FFFFFF",
};

/** The minimal invoice shape the document renders — a saved row or a live draft. */
export interface InvoiceDocData {
  invoiceNumber: string;
  status?: string;
  issueDate: string; // ISO
  dueDate?: string; // ISO
  billTo: {
    name: string;
    contactPerson?: string;
    email?: string;
    address?: string;
    abn?: string;
  };
  from: {
    name: string;
    email?: string;
    address?: string;
    abn?: string;
    gstRegistered: boolean;
    gstRate: number;
    bankName?: string;
    bsb?: string;
    accountNumber?: string;
    accountName?: string;
    paymentDetails?: string;
  };
  lineItems: {
    description: string;
    quantity: number;
    unitPrice: number;
    amount: number;
  }[];
  subtotal: number;
  taxRate: number;
  taxAmount: number;
  total: number;
  currency: string;
  notes?: string;
  terms?: string;
}

const styles = StyleSheet.create({
  page: {
    padding: 34,
    paddingBottom: 46,
    fontSize: 10,
    color: C.ink,
    fontFamily: "Helvetica",
  },
  header: {
    backgroundColor: C.red,
    borderRadius: 10,
    paddingVertical: 16,
    paddingHorizontal: 18,
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
  },
  brandWrap: { flexDirection: "row", alignItems: "center" },
  logo: {
    width: 48,
    height: 48,
    objectFit: "contain",
    marginRight: 10,
  },
  brand: { fontSize: 22, color: C.white, fontFamily: "Helvetica-Bold" },
  docTitle: {
    fontSize: 16,
    color: C.white,
    fontFamily: "Helvetica-Bold",
    textAlign: "right",
  },
  docNumber: {
    fontSize: 9.5,
    color: C.white,
    opacity: 0.9,
    textAlign: "right",
    marginTop: 2,
  },

  metaRow: { flexDirection: "row", marginTop: 16 },
  partyCol: { flex: 1, paddingRight: 12 },
  metaCol: { width: 170 },
  label: {
    fontSize: 7.5,
    color: C.muted,
    fontFamily: "Helvetica-Bold",
    textTransform: "uppercase",
    marginBottom: 3,
  },
  partyName: { fontSize: 11, fontFamily: "Helvetica-Bold", marginBottom: 2 },
  partyLine: { fontSize: 9.5, color: C.ink, lineHeight: 1.35 },
  partyMuted: { fontSize: 9, color: C.muted, lineHeight: 1.35 },

  metaBox: { backgroundColor: C.cream, borderRadius: 8, padding: 10 },
  metaLine: { flexDirection: "row", justifyContent: "space-between", marginBottom: 4 },
  metaKey: { fontSize: 9, color: C.muted },
  metaVal: { fontSize: 9.5, fontFamily: "Helvetica-Bold" },

  // Line-item table
  tableHead: {
    flexDirection: "row",
    backgroundColor: C.cream,
    borderRadius: 5,
    paddingVertical: 6,
    paddingHorizontal: 8,
    marginTop: 20,
  },
  row: {
    flexDirection: "row",
    borderBottom: `1 solid ${C.rule}`,
    paddingVertical: 6,
    paddingHorizontal: 8,
  },
  th: { fontSize: 8.5, color: C.muted, fontFamily: "Helvetica-Bold" },
  cDesc: { flex: 1 },
  cQty: { width: 50, textAlign: "right" },
  cPrice: { width: 80, textAlign: "right" },
  cAmount: { width: 80, textAlign: "right" },
  cell: { fontSize: 9.5 },

  totals: { marginTop: 10, alignItems: "flex-end" },
  totalsLine: { flexDirection: "row", width: 240, justifyContent: "space-between", paddingVertical: 3 },
  totalsKey: { fontSize: 10, color: C.muted },
  totalsVal: { fontSize: 10, fontFamily: "Helvetica-Bold" },
  grandLine: {
    flexDirection: "row",
    width: 240,
    justifyContent: "space-between",
    paddingVertical: 7,
    paddingHorizontal: 8,
    marginTop: 4,
    backgroundColor: C.ink,
    borderRadius: 6,
  },
  grandKey: { fontSize: 11, color: C.white, fontFamily: "Helvetica-Bold" },
  grandVal: { fontSize: 12, color: C.white, fontFamily: "Helvetica-Bold" },

  panel: { backgroundColor: C.cream, borderRadius: 8, padding: 10, marginTop: 18 },
  panelTitle: { fontSize: 8.5, color: C.muted, fontFamily: "Helvetica-Bold", textTransform: "uppercase", marginBottom: 4 },
  panelText: { fontSize: 9.5, color: C.ink, lineHeight: 1.4 },
  payRow: { flexDirection: "row", marginBottom: 2 },
  payLabel: { width: 95, fontSize: 9.5, color: C.muted },
  payValue: { fontSize: 9.5, fontFamily: "Helvetica-Bold", color: C.ink },

  footer: {
    position: "absolute",
    bottom: 24,
    left: 34,
    right: 34,
    fontSize: 8,
    color: C.muted,
    textAlign: "center",
    borderTop: `1 solid ${C.red}`,
    paddingTop: 6,
  },
});

function fmtMoney(n: number, currency: string): string {
  try {
    return new Intl.NumberFormat("en-AU", {
      style: "currency",
      currency: currency || "AUD",
    }).format(n);
  } catch {
    return `$${n.toFixed(2)}`;
  }
}

function fmtDate(iso?: string): string {
  if (!iso) return "—";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "—";
  return d.toLocaleDateString("en-AU", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/** Australian BSB is conventionally shown as XXX-XXX. */
function formatBsb(bsb: string): string {
  const digits = bsb.replace(/\D/g, "");
  return digits.length === 6 ? `${digits.slice(0, 3)}-${digits.slice(3)}` : bsb;
}

function PayRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.payRow}>
      <Text style={styles.payLabel}>{label}</Text>
      <Text style={styles.payValue}>{value}</Text>
    </View>
  );
}

function Party({
  label,
  name,
  contactPerson,
  email,
  address,
  abn,
}: {
  label: string;
  name: string;
  contactPerson?: string;
  email?: string;
  address?: string;
  abn?: string;
}) {
  return (
    <View style={styles.partyCol}>
      <Text style={styles.label}>{label}</Text>
      <Text style={styles.partyName}>{name || "—"}</Text>
      {contactPerson ? <Text style={styles.partyLine}>{contactPerson}</Text> : null}
      {address
        ? address
            .split("\n")
            .map((line, i) => (
              <Text key={i} style={styles.partyLine}>
                {line}
              </Text>
            ))
        : null}
      {email ? <Text style={styles.partyMuted}>{email}</Text> : null}
      {abn ? <Text style={styles.partyMuted}>ABN {abn}</Text> : null}
    </View>
  );
}

export function InvoiceDocument({
  invoice,
  logo,
}: {
  invoice: InvoiceDocData;
  logo?: string | null;
}) {
  const gst = invoice.taxRate > 0;
  const title = gst ? "TAX INVOICE" : "INVOICE";
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <View style={styles.header}>
          <View style={styles.brandWrap}>
            {logo ? <Image src={logo} style={styles.logo} /> : null}
            <Text style={styles.brand}>Lumi</Text>
          </View>
          <View>
            <Text style={styles.docTitle}>{title}</Text>
            {invoice.invoiceNumber ? (
              <Text style={styles.docNumber}>{invoice.invoiceNumber}</Text>
            ) : null}
          </View>
        </View>

        <View style={styles.metaRow}>
          <Party label="From" name={invoice.from.name} email={invoice.from.email} address={invoice.from.address} abn={invoice.from.abn} />
          <Party label="Bill to" name={invoice.billTo.name} contactPerson={invoice.billTo.contactPerson} email={invoice.billTo.email} address={invoice.billTo.address} abn={invoice.billTo.abn} />
          <View style={styles.metaCol}>
            <View style={styles.metaBox}>
              <View style={styles.metaLine}>
                <Text style={styles.metaKey}>Invoice #</Text>
                <Text style={styles.metaVal}>{invoice.invoiceNumber || "Draft"}</Text>
              </View>
              <View style={styles.metaLine}>
                <Text style={styles.metaKey}>Issue date</Text>
                <Text style={styles.metaVal}>{fmtDate(invoice.issueDate)}</Text>
              </View>
              <View style={styles.metaLine}>
                <Text style={styles.metaKey}>Due date</Text>
                <Text style={styles.metaVal}>{fmtDate(invoice.dueDate)}</Text>
              </View>
              <View style={[styles.metaLine, { marginBottom: 0 }]}>
                <Text style={styles.metaKey}>Amount due</Text>
                <Text style={styles.metaVal}>{fmtMoney(invoice.total, invoice.currency)}</Text>
              </View>
            </View>
          </View>
        </View>

        <View style={styles.tableHead}>
          <Text style={[styles.th, styles.cDesc]}>Description</Text>
          <Text style={[styles.th, styles.cQty]}>Qty</Text>
          <Text style={[styles.th, styles.cPrice]}>Unit price</Text>
          <Text style={[styles.th, styles.cAmount]}>Amount</Text>
        </View>
        {invoice.lineItems.map((it, i) => (
          <View key={i} style={styles.row}>
            <Text style={[styles.cell, styles.cDesc]}>{it.description}</Text>
            <Text style={[styles.cell, styles.cQty]}>{it.quantity}</Text>
            <Text style={[styles.cell, styles.cPrice]}>{fmtMoney(it.unitPrice, invoice.currency)}</Text>
            <Text style={[styles.cell, styles.cAmount]}>{fmtMoney(it.amount, invoice.currency)}</Text>
          </View>
        ))}

        <View style={styles.totals}>
          <View style={styles.totalsLine}>
            <Text style={styles.totalsKey}>Subtotal</Text>
            <Text style={styles.totalsVal}>{fmtMoney(invoice.subtotal, invoice.currency)}</Text>
          </View>
          {gst ? (
            <View style={styles.totalsLine}>
              <Text style={styles.totalsKey}>
                GST ({Math.round(invoice.taxRate * 100)}%)
              </Text>
              <Text style={styles.totalsVal}>{fmtMoney(invoice.taxAmount, invoice.currency)}</Text>
            </View>
          ) : null}
          <View style={styles.grandLine}>
            <Text style={styles.grandKey}>Total {invoice.currency}</Text>
            <Text style={styles.grandVal}>{fmtMoney(invoice.total, invoice.currency)}</Text>
          </View>
        </View>

        {invoice.from.bankName ||
        invoice.from.bsb ||
        invoice.from.accountNumber ||
        invoice.from.accountName ||
        invoice.from.paymentDetails ? (
          <View style={styles.panel}>
            <Text style={styles.panelTitle}>Payment details</Text>
            {invoice.from.bankName ? (
              <PayRow label="Bank" value={invoice.from.bankName} />
            ) : null}
            {invoice.from.bsb ? (
              <PayRow label="BSB" value={formatBsb(invoice.from.bsb)} />
            ) : null}
            {invoice.from.accountNumber ? (
              <PayRow label="Account number" value={invoice.from.accountNumber} />
            ) : null}
            {invoice.from.accountName ? (
              <PayRow label="Account name" value={invoice.from.accountName} />
            ) : null}
            {invoice.from.paymentDetails ? (
              <Text style={[styles.panelText, { marginTop: 4 }]}>
                {invoice.from.paymentDetails}
              </Text>
            ) : null}
          </View>
        ) : null}
        {invoice.notes ? (
          <View style={styles.panel}>
            <Text style={styles.panelTitle}>Notes</Text>
            <Text style={styles.panelText}>{invoice.notes}</Text>
          </View>
        ) : null}
        {invoice.terms ? (
          <View style={styles.panel}>
            <Text style={styles.panelTitle}>Terms</Text>
            <Text style={styles.panelText}>{invoice.terms}</Text>
          </View>
        ) : null}
        {!invoice.from.gstRegistered && gst ? (
          <Text style={{ fontSize: 8, color: C.muted, marginTop: 8 }}>
            Note: issuer is marked not registered for GST; confirm GST settings.
          </Text>
        ) : null}

        <Text
          style={styles.footer}
          fixed
          render={({ pageNumber, totalPages }) =>
            `${invoice.from.name} · Lumi Reading Diary · page ${pageNumber} of ${totalPages}`
          }
        />
      </Page>
    </Document>
  );
}

/** Same-origin PNG → data URL so @react-pdf embeds it reliably (skips SVG). */
export async function imageToDataUrl(url: string): Promise<string | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const blob = await res.blob();
    if (!blob.type.startsWith("image/") || blob.type.includes("svg")) return null;
    return await new Promise<string | null>((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () =>
        resolve(typeof reader.result === "string" ? reader.result : null);
      reader.onerror = () => resolve(null);
      reader.readAsDataURL(blob);
    });
  } catch {
    return null;
  }
}

/** Generate + download the invoice PDF client-side (no server round-trip). */
export async function downloadInvoicePdf(
  invoice: InvoiceDocData,
  logo?: string | null
): Promise<void> {
  const blob = await pdf(<InvoiceDocument invoice={invoice} logo={logo} />).toBlob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  const safe = (invoice.invoiceNumber || "draft").replace(/[^\w-]+/g, "-");
  a.href = url;
  a.download = `${safe}.pdf`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/** Generate the PDF as a Blob (for upload / emailing). */
export async function invoicePdfBlob(
  invoice: InvoiceDocData,
  logo?: string | null
): Promise<Blob> {
  return pdf(<InvoiceDocument invoice={invoice} logo={logo} />).toBlob();
}
