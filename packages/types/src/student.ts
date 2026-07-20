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
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  enrolledAt?: FirestoreTimestamp;
  additionalInfo?: Record<string, unknown>;
  enrollmentStatus?: EnrollmentStatus;
  levelHistory: ReadingLevelHistory[];
  stats?: StudentStats;
  /** Materialised access verdict; absent on legacy docs (= no access). */
  access?: StudentAccess;
}

export type EnrollmentStatus = "book_pack" | "direct_purchase" | "not_enrolled";

export type StudentAccessStatus = "active" | "expired" | "suspended";

export type StudentAccessSource =
  | "school_renewal"
  | "book_pack_assumed"
  | "parent_direct"
  | "comp";

/**
 * Materialised, fail-closed access verdict for a student. Written exclusively
 * server-side (renewal callable, subscription trigger, rollover cron, link
 * redemption); clients and security rules read it but never write it. Absent
 * on legacy documents — treated as "no access".
 */
export interface StudentAccess {
  status: StudentAccessStatus;
  /** Calendar year the AU school-year STARTS (e.g. 2026). */
  academicYear: number;
  /** Absolute hard boundary (~31 Jan of the following year). */
  expiresAt: FirestoreTimestamp;
  source?: StudentAccessSource;
  grantedAt?: FirestoreTimestamp;
  grantedBy?: string;
}
