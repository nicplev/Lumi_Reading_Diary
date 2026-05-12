import type { FirestoreTimestamp } from "./common";

export const UserRole = {
  parent: "parent",
  teacher: "teacher",
  schoolAdmin: "schoolAdmin",
} as const;
export type UserRole = (typeof UserRole)[keyof typeof UserRole];

export interface SchoolUser {
  id: string;
  email: string;
  fullName: string;
  role: UserRole;
  schoolId?: string;
  linkedChildren: string[];
  classIds: string[];
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  lastLoginAt?: FirestoreTimestamp;
  preferences?: Record<string, unknown>;
  fcmToken?: string;
}
