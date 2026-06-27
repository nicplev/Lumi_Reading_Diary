/**
 * Read-only "who has this book" snapshot for the school library — the web
 * mirror of the app's `LibraryAssignmentSnapshot`
 * (lib/services/school_library_assignment_service.dart). Computed server-side
 * from active byTitle allocations within their date window.
 */

export interface LibraryAssigneeStudent {
  id: string;
  firstName: string;
  lastName: string;
  classId: string;
  /** Resolved class name; 'Unknown class' if the class can't be found. */
  className: string;
  characterId?: string;
}

export interface LibraryAssignmentViewer {
  role: 'teacher' | 'schoolAdmin';
  /** Classes the viewer teaches — powers the My-class vs Whole-school filter. */
  classIds: string[];
}

export interface LibraryAssignmentSnapshot {
  /** book-key → assigned student ids. Keys are deduped arrays (Sets serialized). */
  studentIdsByBookId: Record<string, string[]>;
  studentIdsByIsbn: Record<string, string[]>;
  studentIdsByNormalizedTitle: Record<string, string[]>;
  /** Directory of only the students referenced above. */
  students: Record<string, LibraryAssigneeStudent>;
  viewer: LibraryAssignmentViewer;
}
