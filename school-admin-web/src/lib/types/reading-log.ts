export type ReadingStatus = 'completed' | 'inProgress' | 'skipped';

export interface ReadingLog {
  id: string;
  studentId: string;
  schoolId: string;
  classId: string;
  date: Date;
  minutesRead: number;
  status: ReadingStatus;
  bookTitles: string[];
  bookIds: string[];
  parentComment?: string;
  teacherComment?: string;
  parentId?: string;
  createdAt: Date;
  updatedAt?: Date;
}
