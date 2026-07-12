import type { FirestoreTimestamp } from "./common";

export const ReadingLevelSchema = {
  none: "none",
  aToZ: "aToZ",
  pmBenchmark: "pmBenchmark",
  lexile: "lexile",
  custom: "custom",
} as const;
export type ReadingLevelSchema =
  (typeof ReadingLevelSchema)[keyof typeof ReadingLevelSchema];

export interface School {
  id: string;
  name: string;
  logoUrl?: string;
  primaryColor?: string;
  secondaryColor?: string;
  levelSchema: ReadingLevelSchema;
  customLevels?: string[];
  termDates: Record<string, FirestoreTimestamp>;
  quietHours: Record<string, string>;
  timezone: string;
  address?: string;
  contactEmail?: string;
  contactPhone?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  createdBy: string;
  settings?: Record<string, unknown>;
  studentCount: number;
  teacherCount: number;
  parentCount: number;
  subscriptionPlan?: string;
  subscriptionExpiry?: FirestoreTimestamp;
  /**
   * Whole-school billing/access model, set by super-admin. Absent on legacy docs
   * (treated as `whole_school_paid`). `whole_school_paid`: the school is invoiced
   * for its whole roster and every rostered student is auto-covered — the
   * per-student subscription surface is hidden. `direct_allowed`: reserved for the
   * future per-student direct-payment channel (not yet functional).
   */
  accessMode?: AccessMode;
  /** Materialised whole-school access verdict; absent on legacy docs (= active). */
  access?: SchoolAccess;
}

export type AccessMode = "whole_school_paid" | "direct_allowed";

export type SchoolAccessStatus = "active" | "suspended";

/**
 * Materialised whole-school access verdict, written server-side by the
 * subscription trigger / rollover cron / off-board wizard. Drives whole-school
 * suspension for staff and families.
 */
export interface SchoolAccess {
  status: SchoolAccessStatus;
  academicYear: number;
  reason?: string;
  updatedAt?: FirestoreTimestamp;
}
