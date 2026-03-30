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
}
