import type { FirestoreTimestamp } from "./common";

export const LinkCodeStatus = {
  active: "active",
  used: "used",
  expired: "expired",
  revoked: "revoked",
} as const;
export type LinkCodeStatus =
  (typeof LinkCodeStatus)[keyof typeof LinkCodeStatus];

export interface StudentLinkCode {
  id: string;
  studentId: string;
  schoolId: string;
  code: string;
  status: LinkCodeStatus;
  createdAt: FirestoreTimestamp;
  expiresAt: FirestoreTimestamp;
  createdBy: string;
  usedBy?: string;
  usedAt?: FirestoreTimestamp;
  revokedBy?: string;
  revokedAt?: FirestoreTimestamp;
  revokeReason?: string;
  metadata?: Record<string, unknown>;
}
