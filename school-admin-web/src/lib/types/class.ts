export interface SchoolClass {
  id: string;
  name: string;
  schoolId: string;
  yearLevel?: string;
  teacherIds: string[];
  studentIds: string[];
  defaultMinutesTarget: number;
  isActive: boolean;
  createdAt: Date;
  createdBy: string;
  metadata?: Record<string, unknown>;
}
