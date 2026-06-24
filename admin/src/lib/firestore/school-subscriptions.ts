import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { SubscriptionStatus, SubscriptionTier } from "@lumi/types";

const COLL = "schoolSubscriptions";
const DEFAULT_TZ = "Australia/Sydney";
const ROLLOVER_DAY = 25;

function toISO(ts: unknown): string {
  if (!ts || typeof ts !== "object") return "";
  if ("toDate" in ts && typeof (ts as { toDate: unknown }).toDate === "function") {
    return (ts as { toDate: () => Date }).toDate().toISOString();
  }
  return "";
}

/**
 * The academic year (calendar year the AU school-year STARTS) in session.
 * Reads config/academicYear when present (single source of truth); otherwise
 * derives it from today, mirroring functions/src/access.ts academicYearForDate.
 */
export async function getCurrentAcademicYear(): Promise<number> {
  const cfg = await getAdminDb().collection("config").doc("academicYear").get();
  const v = cfg.data()?.currentAcademicYear;
  if (typeof v === "number") return v;
  return deriveAcademicYear(new Date());
}

function deriveAcademicYear(d: Date): number {
  const fmt = (opt: Intl.DateTimeFormatOptions) =>
    Number(new Intl.DateTimeFormat("en-CA", { timeZone: DEFAULT_TZ, ...opt }).format(d));
  const year = fmt({ year: "numeric" });
  const month = fmt({ month: "numeric" });
  const day = fmt({ day: "numeric" });
  if (month === 1 && day < ROLLOVER_DAY) return year - 1;
  return year;
}

export interface SchoolSubscriptionRow {
  id: string;
  schoolId: string;
  academicYear: number;
  status: SubscriptionStatus;
  tier?: SubscriptionTier;
  amount?: number;
  currency: string;
  invoiceRef?: string;
  invoicedAt?: string;
  paidAt?: string;
  validFrom?: string;
  validUntil?: string;
  notes?: string;
  updatedBy?: string;
  updatedAt?: string;
}

function rowFromDoc(doc: FirebaseFirestore.DocumentSnapshot): SchoolSubscriptionRow {
  const d = doc.data() ?? {};
  return {
    id: doc.id,
    schoolId: d.schoolId ?? "",
    academicYear: d.academicYear ?? 0,
    status: (d.status ?? "unpaid") as SubscriptionStatus,
    tier: d.tier,
    amount: d.amount,
    currency: d.currency ?? "AUD",
    invoiceRef: d.invoiceRef,
    invoicedAt: toISO(d.invoicedAt) || undefined,
    paidAt: toISO(d.paidAt) || undefined,
    validFrom: toISO(d.validFrom) || undefined,
    validUntil: toISO(d.validUntil) || undefined,
    notes: d.notes,
    updatedBy: d.updatedBy,
    updatedAt: toISO(d.updatedAt) || undefined,
  };
}

/** All subscription rows for a single school, newest year first. */
export async function getSubscriptionsForSchool(
  schoolId: string
): Promise<SchoolSubscriptionRow[]> {
  const snap = await getAdminDb()
    .collection(COLL)
    .where("schoolId", "==", schoolId)
    .get();
  return snap.docs
    .map(rowFromDoc)
    .sort((a, b) => b.academicYear - a.academicYear);
}

/** Every school's subscription row for one academic year (billing dashboard). */
export async function listSubscriptionsForYear(
  academicYear: number
): Promise<SchoolSubscriptionRow[]> {
  const snap = await getAdminDb()
    .collection(COLL)
    .where("academicYear", "==", academicYear)
    .get();
  return snap.docs.map(rowFromDoc);
}

export interface UpsertSubscriptionInput {
  schoolId: string;
  academicYear: number;
  status: SubscriptionStatus;
  tier?: SubscriptionTier;
  amount?: number;
  currency?: string;
  invoiceRef?: string;
  paidAt?: string | null;
  notes?: string;
  updatedBy: string;
}

/**
 * Create or update the `{schoolId}_{academicYear}` row. The T1 Cloud Function
 * (onSchoolSubscriptionWrite) reacts to this write to recompute school.access
 * and cascade student access — this helper only owns the subscription row.
 */
export async function upsertSubscription(
  input: UpsertSubscriptionInput
): Promise<string> {
  const id = `${input.schoolId}_${input.academicYear}`;
  const payload: Record<string, unknown> = {
    schoolId: input.schoolId,
    academicYear: input.academicYear,
    status: input.status,
    currency: input.currency ?? "AUD",
    updatedBy: input.updatedBy,
    updatedAt: FieldValue.serverTimestamp(),
  };
  if (input.tier !== undefined) payload.tier = input.tier;
  if (input.amount !== undefined) payload.amount = input.amount;
  if (input.invoiceRef !== undefined) payload.invoiceRef = input.invoiceRef;
  if (input.notes !== undefined) payload.notes = input.notes;
  if (input.paidAt === null) {
    payload.paidAt = FieldValue.delete();
  } else if (input.paidAt) {
    payload.paidAt = Timestamp.fromDate(new Date(input.paidAt));
  } else if (input.status === "paid") {
    // Stamp paidAt on transition to paid when the caller didn't supply one.
    payload.paidAt = FieldValue.serverTimestamp();
  }

  await getAdminDb().collection(COLL).doc(id).set(payload, { merge: true });
  return id;
}
