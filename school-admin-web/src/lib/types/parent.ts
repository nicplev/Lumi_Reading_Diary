export interface Parent {
  id: string;
  email: string;
  /**
   * Guardian's phone number in E.164 format. Populated when they register
   * with SMS (phone-mandatory rego), and is the only contact detail for
   * parents who sign up without an email.
   */
  phoneNumber?: string;
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
  /**
   * True when this parent's Firebase Auth account no longer exists — the
   * Firestore doc is orphaned (e.g. the Auth user was deleted out-of-band).
   * Such a parent can't sign in, so the UI surfaces them as "Removed" rather
   * than a misleading "Active". The parent list is otherwise purely
   * Firestore-driven and never reflects Auth state.
   */
  authMissing?: boolean;
}
