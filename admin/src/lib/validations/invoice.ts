import { z } from "zod";
import { INVOICE_STATUS_VALUES } from "@lumi/types";

const optionalString = (max: number) =>
  z.string().max(max).optional().or(z.literal(""));

export const billingEntitySchema = z.object({
  legalName: z.string().min(1, "Legal name is required").max(200),
  abn: optionalString(50),
  address: optionalString(500),
  email: z.string().email().optional().or(z.literal("")),
  gstRegistered: z.boolean(),
  gstRate: z.number().min(0).max(1),
  bankName: optionalString(120),
  bsb: optionalString(20),
  accountNumber: optionalString(40),
  accountName: optionalString(120),
  paymentDetails: optionalString(2000),
  pricePerStudent: z.number().nonnegative().optional(),
  paymentTermsDays: z.number().int().min(0).max(365).optional(),
});
export type BillingEntityFormInput = z.infer<typeof billingEntitySchema>;

export const invoiceLineItemSchema = z.object({
  description: z.string().min(1, "Description is required").max(300),
  quantity: z.number().min(0),
  unitPrice: z.number(), // may be negative (discounts)
});

export const invoicePartySchema = z.object({
  name: z.string().min(1, "Recipient name is required").max(200),
  contactPerson: optionalString(200),
  email: z.string().email().optional().or(z.literal("")),
  address: optionalString(500),
  abn: optionalString(50),
});

export const createInvoiceSchema = z.object({
  schoolId: z.string().max(200).optional(),
  academicYear: z.number().int().min(2020).max(2100).optional(),
  issueDate: z.string().min(1), // ISO
  dueDate: z.string().optional(),
  billTo: invoicePartySchema,
  lineItems: z.array(invoiceLineItemSchema).min(1, "Add at least one line item"),
  taxRate: z.number().min(0).max(1),
  currency: z.string().length(3).optional(),
  notes: optionalString(2000),
  terms: optionalString(2000),
  status: z.enum(["draft", "issued"]).optional(),
});
export type CreateInvoiceFormInput = z.infer<typeof createInvoiceSchema>;

export const updateInvoiceStatusSchema = z.object({
  status: z.enum(
    INVOICE_STATUS_VALUES as unknown as [string, ...string[]]
  ),
});
