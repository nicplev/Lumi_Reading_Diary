import type { FirestoreTimestamp } from "./common";

export interface SchoolCode {
  id: string;
  code: string;
  schoolId: string;
  schoolName: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  expiresAt?: FirestoreTimestamp;
  createdBy?: string;
  usageCount?: number;
  maxUsages?: number;
}
