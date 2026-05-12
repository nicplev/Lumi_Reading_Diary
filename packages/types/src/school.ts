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
}
