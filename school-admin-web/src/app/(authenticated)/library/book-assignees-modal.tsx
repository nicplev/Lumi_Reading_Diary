'use client';

import { Modal } from '@/components/lumi/modal';
import { Avatar } from '@/components/lumi/avatar';
import {
  assignedStudentIdsForBook,
  narrowToClasses,
  groupAssigneesByClass,
} from '@/lib/library/assignment-matching';
import type { LibraryAssignmentSnapshot } from '@/lib/types';

/** Read-only sheet listing the students a book is currently assigned to,
 *  grouped by class. Narrowed to the viewer's classes when `viewerClassIds`
 *  is provided (My-class scope); whole school when null. */
export function BookAssigneesModal({
  open,
  onClose,
  book,
  snapshot,
  viewerClassIds,
}: {
  open: boolean;
  onClose: () => void;
  book: { id: string; isbn?: string; title: string } | null;
  snapshot: LibraryAssignmentSnapshot | undefined;
  viewerClassIds: string[] | null;
}) {
  if (!book) return null;

  let ids = snapshot ? assignedStudentIdsForBook(snapshot, book) : new Set<string>();
  if (snapshot && viewerClassIds) ids = narrowToClasses(ids, snapshot, viewerClassIds);
  const groups = snapshot ? groupAssigneesByClass(ids, snapshot) : [];
  const total = ids.size;

  return (
    <Modal open={open} onClose={onClose} title={book.title} size="lg">
      <p className="text-sm text-text-secondary mb-4">
        {total === 0
          ? 'Not currently assigned to any student.'
          : `Currently assigned to ${total} student${total === 1 ? '' : 's'}`}
      </p>
      {groups.length > 0 && (
        <div className="space-y-4">
          {groups.map((g) => (
            <div key={g.classId}>
              <h4 className="text-xs font-semibold uppercase tracking-wider text-text-secondary mb-2">
                {g.className} · {g.students.length}
              </h4>
              <div className="space-y-1.5">
                {g.students.map((s) => (
                  <div key={s.id} className="flex items-center gap-2.5">
                    <Avatar
                      name={`${s.firstName} ${s.lastName}`}
                      characterId={s.characterId}
                      size="sm"
                    />
                    <span className="text-sm text-charcoal">
                      {s.firstName} {s.lastName}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}
