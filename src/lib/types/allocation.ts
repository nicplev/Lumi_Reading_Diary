import type { FirestoreTimestamp } from "./common";

export const AllocationType = {
  byLevel: "byLevel",
  byTitle: "byTitle",
  freeChoice: "freeChoice",
} as const;
export type AllocationType =
  (typeof AllocationType)[keyof typeof AllocationType];

export const AllocationCadence = {
  daily: "daily",
  weekly: "weekly",
  fortnightly: "fortnightly",
  custom: "custom",
} as const;
export type AllocationCadence =
  (typeof AllocationCadence)[keyof typeof AllocationCadence];

export interface AllocationBookItem {
  id: string;
  title: string;
  bookId?: string;
  isbn?: string;
  isDeleted: boolean;
  addedAt?: FirestoreTimestamp;
  addedBy?: string;
  metadata?: Record<string, unknown>;
}

export interface StudentAllocationOverride {
  studentId: string;
  removedItemIds: string[];
  addedItems: AllocationBookItem[];
  updatedAt?: FirestoreTimestamp;
  updatedBy?: string;
  metadata?: Record<string, unknown>;
}

export interface Allocation {
  id: string;
  schoolId: string;
  classId: string;
  teacherId: string;
  studentIds: string[];
  type: AllocationType;
  cadence: AllocationCadence;
  targetMinutes: number;
  startDate: FirestoreTimestamp;
  endDate: FirestoreTimestamp;
  levelStart?: string;
  levelEnd?: string;
  bookIds?: string[];
  bookTitles?: string[];
  assignmentItems?: AllocationBookItem[];
  studentOverrides?: Record<string, StudentAllocationOverride>;
  schemaVersion: number;
  isRecurring: boolean;
  templateName?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  createdBy: string;
  metadata?: Record<string, unknown>;
}
