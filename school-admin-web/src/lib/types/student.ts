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

/** Why a student was soft-archived (rollover import or manual portal action). */
export type ArchivedReason = 'graduated' | 'left' | 'manual';

export type StudentAccessStatus = 'active' | 'expired' | 'suspended' | 'revoked';

export type StudentAccessSource =
  | 'school_renewal'
  | 'book_pack_assumed'
  | 'parent_direct'
  | 'comp';

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
  expiresAt: Date;
  source?: StudentAccessSource;
  grantedAt?: Date;
  grantedBy?: string;
  revokedAt?: Date;
  revokedBy?: string;
  revokeReason?: string;
}

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
  profileImageUrl?: string;
  /** Chosen Lumi character id (Firestore field + PNG stem); see lib/characters.ts. */
  characterId?: string;
  isActive: boolean;
  /**
   * Soft-archive marker. `isActive: false` is the universal hiding mechanism
   * (every roster/report surface already filters on it); `status: 'archived'`
   * distinguishes an archived student (restorable, history kept) from any other
   * inactive state. Set by the archive flow, cleared on restore.
   */
  status?: 'archived';
  archivedAt?: Date;
  archivedReason?: ArchivedReason;
  archivedBy?: string;
  createdAt: Date;
  enrolledAt?: Date;
  additionalInfo?: Record<string, unknown>;
  enrollmentStatus?: EnrollmentStatus;
  parentEmail?: string;
  /** Materialised access verdict; absent on legacy docs (= no access). */
  access?: StudentAccess;
  levelHistory: ReadingLevelHistory[];
  stats?: StudentStats;
  /** Denormalized guardian projections keyed by parent UID. */
  guardianProfiles: Record<string, GuardianProfile>;
}
