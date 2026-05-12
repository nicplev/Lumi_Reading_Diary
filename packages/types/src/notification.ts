import type { FirestoreTimestamp } from "./common";

export interface Notification {
  id: string;
  userId?: string;
  parentUserId?: string;
  schoolId: string;
  title: string;
  body: string;
  type: string;
  isRead: boolean;
  createdAt: FirestoreTimestamp;
  metadata?: Record<string, unknown>;
}
