export interface Parent {
  id: string;
  email: string;
  fullName: string;
  schoolId: string;
  linkedChildren: string[];
  isActive: boolean;
  createdAt: Date;
  lastLoginAt?: Date;
  /**
   * The guardian's relationship to their child(ren) — e.g. Mum, Dad,
   * Grandparent, Guardian, or a free-text value. Set during registration in
   * the parent app. Undefined for legacy parents.
   */
  relationshipLabel?: string;
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
