import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import type { BillingEntity } from "@lumi/types";

const BILLING_ENTITY_DOC = "billingEntity";

// Placeholder defaults — Lumi's real legal name / ABN / GST / bank details must
// be entered via the Billing settings screen before invoices are legally valid.
const DEFAULT_ENTITY: BillingEntity = {
  legalName: "Lumi Reading",
  abn: "",
  address: "",
  email: "accounts@lumi-reading.com",
  gstRegistered: false,
  gstRate: 0.1,
  paymentDetails: "",
  pricePerStudent: undefined,
  paymentTermsDays: 30,
};

export async function getBillingEntity(): Promise<BillingEntity> {
  const snap = await getAdminDb()
    .collection("config")
    .doc(BILLING_ENTITY_DOC)
    .get();
  if (!snap.exists) return { ...DEFAULT_ENTITY };
  const d = snap.data()!;
  return {
    legalName: d.legalName ?? DEFAULT_ENTITY.legalName,
    abn: d.abn ?? "",
    address: d.address ?? "",
    email: d.email ?? DEFAULT_ENTITY.email,
    gstRegistered: d.gstRegistered ?? false,
    gstRate: typeof d.gstRate === "number" ? d.gstRate : 0.1,
    paymentDetails: d.paymentDetails ?? "",
    pricePerStudent:
      typeof d.pricePerStudent === "number" ? d.pricePerStudent : undefined,
    paymentTermsDays:
      typeof d.paymentTermsDays === "number" ? d.paymentTermsDays : 30,
  };
}

export type BillingEntityInput = Omit<
  BillingEntity,
  "updatedBy" | "updatedAt"
> & { updatedBy: string };

export async function setBillingEntity(
  input: BillingEntityInput
): Promise<void> {
  const { updatedBy, ...rest } = input;
  await getAdminDb()
    .collection("config")
    .doc(BILLING_ENTITY_DOC)
    .set(
      { ...rest, updatedBy, updatedAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
}
