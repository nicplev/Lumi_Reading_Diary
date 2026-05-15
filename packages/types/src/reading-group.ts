import type { FirestoreTimestamp } from "./common";

export interface ReadingGroup {
  id: string;
  classId: string;
  schoolId: string;
  name: string;
  description?: string;
  readingLevel?: string;
  studentIds: string[];
  color?: string;
  targetMinutes: number;
  createdAt: FirestoreTimestamp;
  createdBy: string;
  updatedAt?: FirestoreTimestamp;
  isActive: boolean;
  settings?: Record<string, unknown>;
}
