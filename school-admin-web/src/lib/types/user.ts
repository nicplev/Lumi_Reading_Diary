export type UserRole = 'teacher' | 'schoolAdmin' | 'parent';

export interface SchoolUser {
  id: string;
  email: string;
  fullName: string;
  role: UserRole;
  schoolId: string;
  classIds: string[];
  isActive: boolean;
  createdAt: Date;
  lastLoginAt?: Date;
  profileImageUrl?: string;
  phone?: string;
  pendingDeletion?: boolean;
  scheduledDeletionAt?: Date;
  /**
   * Set when a staff account is created via bulk import with an
   * auto-generated temporary password. Advisory only — login is not
   * blocked. The plaintext password itself lives in the Admin-SDK-only
   * `staffCredentials` collection, never on this (teacher-readable) doc.
   */
  mustChangePassword?: boolean;
  /**
   * When the temp password was issued. The Users screen derives a
   * "temp password pending" indicator from this vs. lastLoginAt, so it
   * self-clears once the staff member logs in.
   */
  tempPasswordCreatedAt?: Date;
}
