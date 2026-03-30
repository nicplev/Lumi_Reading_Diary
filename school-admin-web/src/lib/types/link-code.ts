export type LinkCodeStatus = 'active' | 'used' | 'expired' | 'revoked';

export interface StudentLinkCode {
  id: string;
  code: string;
  schoolId: string;
  studentId: string;
  studentName: string;
  classId: string;
  status: LinkCodeStatus;
  createdAt: Date;
  expiresAt: Date;
  usedAt?: Date;
  usedBy?: string;
  createdBy: string;
}
