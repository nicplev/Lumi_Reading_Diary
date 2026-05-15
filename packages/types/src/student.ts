import type { FirestoreTimestamp } from "./common";

export interface ReadingLevelHistory {
  level: string;
  changedAt: FirestoreTimestamp;
  changedBy: string;
  reason?: string;
}

export interface StudentStats {
  totalMinutesRead: number;
  totalBooksRead: number;
  currentStreak: number;
  longestStreak: number;
  lastReadingDate?: FirestoreTimestamp;
  averageMinutesPerDay: number;
  totalReadingDays: number;
}

export interface Student {
  id: string;
  firstName: string;
  lastName: string;
  studentId?: string;
  schoolId: string;
  classId: string;
  currentReadingLevel?: string;
  currentReadingLevelIndex?: number;
  readingLevelUpdatedAt?: FirestoreTimestamp;
  readingLevelUpdatedBy?: string;
  readingLevelSource?: string;
  parentIds: string[];
  dateOfBirth?: FirestoreTimestamp;
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  enrolledAt?: FirestoreTimestamp;
  additionalInfo?: Record<string, unknown>;
  levelHistory: ReadingLevelHistory[];
  stats?: StudentStats;
}
