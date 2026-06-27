import type { LibraryAssignmentSnapshot, LibraryAssigneeStudent } from '@/lib/types';

/** Title normalization shared by the snapshot builder and the matcher so keys
 *  line up. Mirrors the app's `BookLookupService.normalizeTitle`. */
export function normalizeTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, ' ');
}

/** The set of student ids currently assigned this book, matched by bookId, then
 *  ISBN (incl. the `isbn_<isbn>` bookId form), then normalized title — the exact
 *  precedence the app uses in `assignedStudentIdsForBook`. */
export function assignedStudentIdsForBook(
  snap: LibraryAssignmentSnapshot,
  book: { id: string; isbn?: string; title: string }
): Set<string> {
  const ids = new Set<string>();

  const bookId = book.id?.trim();
  if (bookId) (snap.studentIdsByBookId[bookId] ?? []).forEach((id) => ids.add(id));

  const isbn = book.isbn?.trim();
  if (isbn) {
    (snap.studentIdsByIsbn[isbn] ?? []).forEach((id) => ids.add(id));
    (snap.studentIdsByBookId[`isbn_${isbn}`] ?? []).forEach((id) => ids.add(id));
  }

  const nt = normalizeTitle(book.title ?? '');
  if (nt) (snap.studentIdsByNormalizedTitle[nt] ?? []).forEach((id) => ids.add(id));

  return ids;
}

/** Narrow an assignee set to students in the given classes (My-class filter). */
export function narrowToClasses(
  ids: Set<string>,
  snap: LibraryAssignmentSnapshot,
  classIds: string[]
): Set<string> {
  const allow = new Set(classIds);
  const out = new Set<string>();
  for (const id of ids) {
    const s = snap.students[id];
    if (s && allow.has(s.classId)) out.add(id);
  }
  return out;
}

export interface AssigneeClassGroup {
  classId: string;
  className: string;
  students: LibraryAssigneeStudent[];
}

/** Group assignees by class, classes sorted by name and students by first name. */
export function groupAssigneesByClass(
  ids: Set<string>,
  snap: LibraryAssignmentSnapshot
): AssigneeClassGroup[] {
  const byClass = new Map<string, AssigneeClassGroup>();
  for (const id of ids) {
    const s = snap.students[id];
    if (!s) continue;
    let g = byClass.get(s.classId);
    if (!g) {
      g = { classId: s.classId, className: s.className, students: [] };
      byClass.set(s.classId, g);
    }
    g.students.push(s);
  }
  const groups = [...byClass.values()];
  for (const g of groups) {
    g.students.sort((a, b) => a.firstName.localeCompare(b.firstName));
  }
  groups.sort((a, b) => a.className.localeCompare(b.className));
  return groups;
}
