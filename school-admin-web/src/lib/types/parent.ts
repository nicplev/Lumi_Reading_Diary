export interface Parent {
  id: string;
  email: string;
  fullName: string;
  schoolId: string;
  linkedChildren: string[];
  isActive: boolean;
  createdAt: Date;
  lastLoginAt?: Date;
}

export interface LinkedStudent {
  id: string;
  firstName: string;
  lastName: string;
  classId: string;
}

export interface ParentWithStudents extends Parent {
  linkedStudents: LinkedStudent[];
}
