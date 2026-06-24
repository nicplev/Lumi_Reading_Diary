import type { FirestoreTimestamp } from "./common";

/**
 * Lumi → School annual platform subscription. Stored top-level at
 * `schoolSubscriptions/{schoolId}_{academicYear}` so the Lumi "who's paid"
 * dashboard is a single collection query. Invoiced manually outside Lumi; this
 * record is the source of truth for whether a school's access is on.
 */
export type SubscriptionStatus =
  | "paid"
  | "unpaid"
  | "comp"
  | "trial"
  | "grace"
  | "cancelled";

/** Statuses that grant active access to the school for the year. */
export const ACTIVE_SUBSCRIPTION_STATUSES: readonly SubscriptionStatus[] = [
  "paid",
  "comp",
  "trial",
  "grace",
];

export function isActiveSubscriptionStatus(
  status: SubscriptionStatus | string | undefined | null
): boolean {
  return (
    status != null &&
    (ACTIVE_SUBSCRIPTION_STATUSES as readonly string[]).includes(status)
  );
}

export type SubscriptionTier = "S" | "M" | "L" | "XL";

export interface SubscriptionTierBand {
  tier: SubscriptionTier;
  minStudents: number;
  maxStudents: number | null;
}

/** Placeholder bands — $ amounts are set per-row by Lumi staff for now. */
export const SUBSCRIPTION_TIERS: readonly SubscriptionTierBand[] = [
  { tier: "S", minStudents: 1, maxStudents: 150 },
  { tier: "M", minStudents: 151, maxStudents: 400 },
  { tier: "L", minStudents: 401, maxStudents: 800 },
  { tier: "XL", minStudents: 801, maxStudents: null },
];

export function tierForStudentCount(count: number): SubscriptionTier {
  for (const band of SUBSCRIPTION_TIERS) {
    if (
      count >= band.minStudents &&
      (band.maxStudents == null || count <= band.maxStudents)
    ) {
      return band.tier;
    }
  }
  return "S";
}

export interface SchoolSubscription {
  /** `{schoolId}_{academicYear}`. */
  id: string;
  schoolId: string;
  /** Calendar year the AU school-year STARTS. */
  academicYear: number;
  status: SubscriptionStatus;
  tier?: SubscriptionTier;
  amount?: number;
  currency: string; // 'AUD'
  invoiceRef?: string;
  invoicedAt?: FirestoreTimestamp;
  paidAt?: FirestoreTimestamp;
  validFrom?: FirestoreTimestamp;
  validUntil?: FirestoreTimestamp;
  notes?: string;
  updatedBy?: string;
  updatedAt?: FirestoreTimestamp;
}

/**
 * Global academic-year boundary. Single document at `config/academicYear`,
 * the single source of truth for the rollover/expiry boundary, read by the
 * cron, both portals, and the app.
 */
export interface AcademicYearConfig {
  currentAcademicYear: number;
  /** ISO date the rollover cron advances the year (~25 Jan). */
  rolloverDate: string;
  /** ISO timestamp all current-year student access hard-expires (~31 Jan). */
  hardExpiry: string;
  timezone: string; // 'Australia/Sydney'
}
