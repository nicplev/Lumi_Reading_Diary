import type { FirestoreTimestamp } from "./common";

/**
 * Lumi invoicing. Invoices are super-admin-created records stored top-level at
 * `invoices/{invoiceId}` (a global register, queryable across schools). The
 * issuer ("from") entity is snapshotted onto each invoice so historical
 * invoices keep their details even if `config/billingEntity` later changes.
 */
export type InvoiceStatus = "draft" | "issued" | "paid" | "void";

/** Statuses in display order. */
export const INVOICE_STATUS_VALUES: readonly InvoiceStatus[] = [
  "draft",
  "issued",
  "paid",
  "void",
];

export interface InvoiceLineItem {
  description: string;
  quantity: number;
  /** Unit price in dollars (not cents). */
  unitPrice: number;
  /** quantity * unitPrice, in dollars. Recomputed server-side, never trusted from the client. */
  amount: number;
}

/** A billing party — either the recipient (`billTo`) or the issuer (`from`). */
export interface InvoiceParty {
  name: string;
  contactPerson?: string;
  email?: string;
  /** Single free-text block (multi-line). */
  address?: string;
  abn?: string;
}

/** The issuer block, snapshotted from `config/billingEntity` at issue time. */
export interface InvoiceIssuer extends InvoiceParty {
  gstRegistered: boolean;
  gstRate: number;
  bankName?: string;
  bsb?: string;
  accountNumber?: string;
  accountName?: string;
  paymentDetails?: string;
}

export interface Invoice {
  id: string;
  /** e.g. "LUMI-2026-0001"; empty string until the invoice is issued. */
  invoiceNumber: string;
  status: InvoiceStatus;
  /** The school this invoice relates to (optional — invoices can be school-agnostic). */
  schoolId?: string;
  academicYear?: number;
  issueDate: FirestoreTimestamp;
  dueDate?: FirestoreTimestamp;
  /** Editable recipient — school office, KAKA, or anyone. */
  billTo: InvoiceParty;
  from: InvoiceIssuer;
  lineItems: InvoiceLineItem[];
  subtotal: number;
  /** Fraction, e.g. 0.10 for 10% GST, or 0. */
  taxRate: number;
  taxAmount: number;
  total: number;
  currency: string; // 'AUD'
  notes?: string;
  terms?: string;
  /** Storage path of the last generated PDF (set when emailed/snapshotted). */
  pdfStoragePath?: string;
  lastEmailedAt?: FirestoreTimestamp;
  lastEmailedTo?: string;
  createdBy?: string;
  createdAt?: FirestoreTimestamp;
  updatedBy?: string;
  updatedAt?: FirestoreTimestamp;
}

/**
 * Lumi's own billing/legal entity. Single document at `config/billingEntity`,
 * super-admin editable, snapshotted onto every invoice's `from`. Placeholders
 * until Lumi's real ABN/entity/GST/bank details are entered — invoices are not
 * legally valid until then.
 */
export interface BillingEntity {
  legalName: string;
  abn?: string;
  address?: string;
  email?: string;
  gstRegistered: boolean;
  /** Default GST fraction applied to new invoices, e.g. 0.10. */
  gstRate: number;
  /** Structured bank details shown labelled on invoices. */
  bankName?: string;
  bsb?: string;
  accountNumber?: string;
  accountName?: string;
  /** Extra free-text payment instructions shown below the bank details. */
  paymentDetails?: string;
  /** Default price per student the invoice builder pre-fills (dollars). */
  pricePerStudent?: number;
  /** Days after issue an invoice is due (default 30). */
  paymentTermsDays?: number;
  updatedBy?: string;
  updatedAt?: FirestoreTimestamp;
}
