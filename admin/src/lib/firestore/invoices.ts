import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type {
  Invoice,
  InvoiceIssuer,
  InvoiceLineItem,
  InvoiceParty,
  InvoiceStatus,
} from "@lumi/types";
import { getBillingEntity } from "./billing-entity";

const INVOICES = "invoices";
const COUNTER_DOC = "invoiceCounters";

function round2(n: number): number {
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function toISO(ts: unknown): string | undefined {
  if (ts && typeof ts === "object" && "toDate" in ts &&
      typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return undefined;
}

/** Compute line amounts + totals server-side — client-supplied amounts are never trusted. */
function computeTotals(
  rawItems: { description: string; quantity: number; unitPrice: number }[],
  taxRate: number
): {
  lineItems: InvoiceLineItem[];
  subtotal: number;
  taxAmount: number;
  total: number;
} {
  const lineItems = rawItems.map((it) => ({
    description: it.description,
    quantity: it.quantity,
    unitPrice: it.unitPrice,
    amount: round2(it.quantity * it.unitPrice),
  }));
  const subtotal = round2(lineItems.reduce((s, it) => s + it.amount, 0));
  const taxAmount = round2(subtotal * taxRate);
  const total = round2(subtotal + taxAmount);
  return { lineItems, subtotal, taxAmount, total };
}

/** Allocate the next invoice number for a calendar year, transactionally (gapless within a run). */
async function allocateInvoiceNumber(year: number): Promise<string> {
  const db = getAdminDb();
  const ref = db.collection("config").doc(COUNTER_DOC);
  const seq = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists
      ? (snap.data()?.[String(year)] as number | undefined)
      : undefined;
    const next = (typeof current === "number" ? current : 0) + 1;
    tx.set(ref, { [String(year)]: next }, { merge: true });
    return next;
  });
  return `LUMI-${year}-${String(seq).padStart(4, "0")}`;
}

/** Client-facing invoice with ISO string dates (Timestamps serialised out). */
export interface InvoiceRow
  extends Omit<
    Invoice,
    "issueDate" | "dueDate" | "createdAt" | "updatedAt" | "lastEmailedAt"
  > {
  issueDate: string;
  dueDate?: string;
  createdAt?: string;
  updatedAt?: string;
  lastEmailedAt?: string;
}

function rowFromDoc(
  id: string,
  d: FirebaseFirestore.DocumentData
): InvoiceRow {
  return {
    id,
    invoiceNumber: d.invoiceNumber ?? "",
    status: (d.status ?? "draft") as InvoiceStatus,
    schoolId: d.schoolId,
    academicYear: d.academicYear,
    issueDate: toISO(d.issueDate) ?? "",
    dueDate: toISO(d.dueDate),
    billTo: d.billTo ?? { name: "" },
    from: d.from,
    lineItems: d.lineItems ?? [],
    subtotal: d.subtotal ?? 0,
    taxRate: d.taxRate ?? 0,
    taxAmount: d.taxAmount ?? 0,
    total: d.total ?? 0,
    currency: d.currency ?? "AUD",
    notes: d.notes,
    terms: d.terms,
    pdfStoragePath: d.pdfStoragePath,
    lastEmailedAt: toISO(d.lastEmailedAt),
    lastEmailedTo: d.lastEmailedTo,
    createdBy: d.createdBy,
    createdAt: toISO(d.createdAt),
    updatedBy: d.updatedBy,
    updatedAt: toISO(d.updatedAt),
  };
}

export interface CreateInvoiceInput {
  schoolId?: string;
  academicYear?: number;
  issueDate: string; // ISO
  dueDate?: string; // ISO
  billTo: InvoiceParty;
  lineItems: { description: string; quantity: number; unitPrice: number }[];
  taxRate: number;
  currency?: string;
  notes?: string;
  terms?: string;
  status?: "draft" | "issued";
  createdBy: string;
}

export async function createInvoice(
  input: CreateInvoiceInput
): Promise<InvoiceRow> {
  const db = getAdminDb();
  const entity = await getBillingEntity();
  const from: InvoiceIssuer = {
    name: entity.legalName,
    email: entity.email,
    address: entity.address,
    abn: entity.abn,
    gstRegistered: entity.gstRegistered,
    gstRate: entity.gstRate,
    bankName: entity.bankName,
    bsb: entity.bsb,
    accountNumber: entity.accountNumber,
    accountName: entity.accountName,
    paymentDetails: entity.paymentDetails,
  };

  const { lineItems, subtotal, taxAmount, total } = computeTotals(
    input.lineItems,
    input.taxRate
  );

  const issueDate = new Date(input.issueDate);
  const status: InvoiceStatus = input.status ?? "issued";
  // Number is allocated on creation (every saved invoice is numbered).
  const invoiceNumber = await allocateInvoiceNumber(issueDate.getFullYear());

  const ref = db.collection(INVOICES).doc();
  const doc: Record<string, unknown> = {
    invoiceNumber,
    status,
    issueDate: Timestamp.fromDate(issueDate),
    billTo: input.billTo,
    from,
    lineItems,
    subtotal,
    taxRate: input.taxRate,
    taxAmount,
    total,
    currency: input.currency ?? "AUD",
    createdBy: input.createdBy,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (input.schoolId) doc.schoolId = input.schoolId;
  if (typeof input.academicYear === "number") doc.academicYear = input.academicYear;
  if (input.dueDate) doc.dueDate = Timestamp.fromDate(new Date(input.dueDate));
  if (input.notes) doc.notes = input.notes;
  if (input.terms) doc.terms = input.terms;

  await ref.set(doc);

  // Write-back: link the invoice to an existing subscription row for the same
  // school + year (invoiceRef + invoicedAt). Never creates a subscription row.
  if (input.schoolId && typeof input.academicYear === "number") {
    const subRef = db
      .collection("schoolSubscriptions")
      .doc(`${input.schoolId}_${input.academicYear}`);
    const subSnap = await subRef.get();
    if (subSnap.exists) {
      await subRef.set(
        { invoiceRef: invoiceNumber, invoicedAt: Timestamp.fromDate(issueDate) },
        { merge: true }
      );
    }
  }

  const snap = await ref.get();
  return rowFromDoc(ref.id, snap.data()!);
}

export async function listInvoices(options?: {
  schoolId?: string;
  status?: InvoiceStatus;
  limit?: number;
}): Promise<InvoiceRow[]> {
  let query: FirebaseFirestore.Query = getAdminDb()
    .collection(INVOICES)
    .orderBy("createdAt", "desc");
  if (options?.schoolId) query = query.where("schoolId", "==", options.schoolId);
  if (options?.status) query = query.where("status", "==", options.status);
  query = query.limit(options?.limit ?? 500);
  const snap = await query.get();
  return snap.docs.map((doc) => rowFromDoc(doc.id, doc.data()));
}

export async function getInvoice(id: string): Promise<InvoiceRow | null> {
  const snap = await getAdminDb().collection(INVOICES).doc(id).get();
  if (!snap.exists) return null;
  return rowFromDoc(snap.id, snap.data()!);
}

export async function updateInvoiceStatus(
  id: string,
  status: InvoiceStatus,
  updatedBy: string
): Promise<void> {
  await getAdminDb()
    .collection(INVOICES)
    .doc(id)
    .update({
      status,
      updatedBy,
      updatedAt: FieldValue.serverTimestamp(),
    });
}
