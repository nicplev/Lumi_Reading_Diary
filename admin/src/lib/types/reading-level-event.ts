import type { FirestoreTimestamp } from "./common";

export interface ReadingLevelEvent {
  id: string;
  studentId: string;
  schoolId: string;
  classId: string;
  fromLevel?: string;
  toLevel?: string;
  fromLevelIndex?: number;
  toLevelIndex?: number;
  reason?: string;
  source: string;
  changedByUserId: string;
  changedByRole: string;
  changedByName: string;
  createdAt: FirestoreTimestamp;
}
