export type AllocationCadence = 'daily' | 'weekly' | 'fortnightly' | 'custom';
export type AllocationType = 'byLevel' | 'byTitle' | 'freeChoice';

export interface AllocationBookItem {
  id: string;
  title: string;
  bookId?: string;
  isbn?: string;
  isDeleted: boolean;
  addedAt?: Date;
  addedBy?: string;
  metadata?: Record<string, unknown>;
}

export interface StudentAllocationOverride {
  studentId: string;
  removedItemIds: string[];
  addedItems: AllocationBookItem[];
  updatedAt?: Date;
  updatedBy?: string;
  metadata?: Record<string, unknown>;
}

export interface Allocation {
  id: string;
  schoolId: string;
  classId: string;
  teacherId: string;
  studentIds: string[];
  type: AllocationType;
  cadence: AllocationCadence;
  targetMinutes: number;
  startDate: Date;
  endDate: Date;
  levelStart?: string;
  levelEnd?: string;
  bookIds?: string[];
  bookTitles?: string[];
  assignmentItems?: AllocationBookItem[];
  studentOverrides?: Record<string, StudentAllocationOverride>;
  schemaVersion: number;
  isRecurring: boolean;
  templateName?: string;
  isActive: boolean;
  createdAt: Date;
  createdBy: string;
  metadata?: Record<string, unknown>;
}
