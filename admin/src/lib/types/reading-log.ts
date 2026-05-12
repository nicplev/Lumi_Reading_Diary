import type { FirestoreTimestamp } from "./common";

export const LogStatus = {
  completed: "completed",
  partial: "partial",
  skipped: "skipped",
  pending: "pending",
} as const;
export type LogStatus = (typeof LogStatus)[keyof typeof LogStatus];

export const ReadingFeeling = {
  hard: "hard",
  tricky: "tricky",
  okay: "okay",
  good: "good",
  great: "great",
} as const;
export type ReadingFeeling =
  (typeof ReadingFeeling)[keyof typeof ReadingFeeling];

export interface ReadingLog {
  id: string;
  studentId: string;
  parentId: string;
  schoolId: string;
  classId: string;
  date: FirestoreTimestamp;
  minutesRead: number;
  targetMinutes: number;
  status: LogStatus;
  bookTitles: string[];
  notes?: string;
  photoUrls?: string[];
  isOfflineCreated: boolean;
  createdAt: FirestoreTimestamp;
  syncedAt?: FirestoreTimestamp;
  allocationId?: string;
  metadata?: Record<string, unknown>;
  childFeeling?: ReadingFeeling;
  parentComment?: string;
  parentCommentSelections: string[];
  parentCommentFreeText?: string;
  teacherComment?: string;
  commentedAt?: FirestoreTimestamp;
  commentedBy?: string;
}
