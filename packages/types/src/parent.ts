import type { FirestoreTimestamp } from "./common";

export interface Parent {
  id: string;
  email: string;
  fullName: string;
  role: "parent";
  schoolId: string;
  linkedChildren: string[];
  profileImageUrl?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  lastLoginAt?: FirestoreTimestamp;
  preferences?: Record<string, unknown>;
  fcmToken?: string;
}
