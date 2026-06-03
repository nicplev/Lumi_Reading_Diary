export interface StudentStats {
  totalMinutesRead: number;
  totalBooksRead: number;
  currentStreak: number;
  longestStreak: number;
  lastReadingDate?: Date;
  averageMinutesPerDay: number;
  totalReadingDays: number;
}

export interface ReadingLevelHistory {
  level: string;
  changedAt: Date;
  changedBy: string;
  reason?: string;
}

export type EnrollmentStatus = 'book_pack' | 'direct_purchase' | 'not_enrolled';

/**
 * Minimal projection of a linked guardian, denormalized onto the student doc
 * and maintained server-side by the syncGuardianProfiles Cloud Function.
 * Deliberately carries name + relationship label only — never email/phone.
 * Keyed by parent UID.
 */
export interface GuardianProfile {
  name: string;
  relationshipLabel?: string | null;
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
  readingLevelUpdatedAt?: Date;
  readingLevelUpdatedBy?: string;
  readingLevelSource?: string;
  parentIds: string[];
  dateOfBirth?: Date;
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: Date;
  enrolledAt?: Date;
  additionalInfo?: Record<string, unknown>;
  enrollmentStatus?: EnrollmentStatus;
  parentEmail?: string;
  levelHistory: ReadingLevelHistory[];
  stats?: StudentStats;
  /** Denormalized guardian projections keyed by parent UID. */
  guardianProfiles: Record<string, GuardianProfile>;
}
