import type { ReadingLevelSchema } from './school';

export interface ReadingLevelEvent {
  id: string;
  studentId: string;
  schoolId: string;
  classId: string;
  fromLevel?: string;
  toLevel?: string;
  fromLevelIndex?: number;
  toLevelIndex?: number;
  reason?: string;
  source: string;
  changedByUserId: string;
  changedByRole: string;
  changedByName: string;
  createdAt: Date;
}

export interface ReadingLevelOption {
  value: string;
  shortLabel: string;
  displayLabel: string;
  sortIndex: number;
  schema: ReadingLevelSchema;
  colorHex?: string;
}

export interface ReadingGroup {
  id: string;
  name: string;
  schoolId: string;
  classId: string;
  teacherId: string;
  studentIds: string[];
  readingLevel?: string;
  color?: string;
  isActive: boolean;
  createdAt: Date;
}
