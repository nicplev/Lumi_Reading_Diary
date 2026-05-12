import type { FirestoreTimestamp } from "./common";

export interface Class {
  id: string;
  schoolId: string;
  name: string;
  yearLevel?: string;
  room?: string;
  teacherId: string;
  assistantTeacherId?: string;
  teacherIds: string[];
  studentIds: string[];
  defaultMinutesTarget: number;
  description?: string;
  isActive: boolean;
  createdAt: FirestoreTimestamp;
  createdBy: string;
  settings?: Record<string, unknown>;
}
