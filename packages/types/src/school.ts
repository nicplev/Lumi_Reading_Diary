import type { FirestoreTimestamp } from "./common";

export const ReadingLevelSchema = {
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
  /** Materialised whole-school access verdict; absent on legacy docs (= active). */
  access?: SchoolAccess;
}

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
