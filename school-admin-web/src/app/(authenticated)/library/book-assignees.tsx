'use client';

import { useState } from 'react';
import { Avatar } from '@/components/lumi/avatar';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useLibraryAssignments } from '@/lib/hooks/use-library-assignments';
import {
  assignedStudentIdsForBook,
  narrowToClasses,
  groupAssigneesByClass,
} from '@/lib/library/assignment-matching';

/** Read-only "who has this book" section, shown inside the book detail modal.
 *  Lists assignees grouped by class; teachers get a My-class / Whole-school
 *  toggle. Self-contained — reuses the cached library-assignments query. */
export function BookAssignees({ book }: { book: { id: string; isbn?: string; title: string } }) {
  const { data: snapshot } = useLibraryAssignments();
  const viewer = snapshot?.viewer;
  const showToggle = viewer?.role === 'teacher' && viewer.classIds.length > 0;
  const [scope, setScope] = useState<'myClass' | 'school'>('myClass');
  const narrowIds = showToggle && scope === 'myClass' ? viewer!.classIds : null;

  if (!snapshot) {
    return <p className="text-sm text-text-secondary">Loading assignments…</p>;
  }

  let ids = assignedStudentIdsForBook(snapshot, book);
  if (narrowIds) ids = narrowToClasses(ids, snapshot, narrowIds);
  const groups = groupAssigneesByClass(ids, snapshot);
  const total = ids.size;

  return (
    <div>
      <div className="flex items-center justify-between gap-2 mb-2">
        <p className="text-xs font-semibold text-text-secondary uppercase tracking-wider">Assigned to</p>
        {showToggle && (
          <div className="flex items-center gap-1.5">
            <FilterChip label="My class" selected={scope === 'myClass'} onClick={() => setScope('myClass')} />
            <FilterChip label="Whole school" selected={scope === 'school'} onClick={() => setScope('school')} />
          </div>
        )}
      </div>

      <p className="text-sm text-charcoal mb-3">
        {total === 0
          ? 'Not currently assigned to any student.'
          : `${total} student${total === 1 ? '' : 's'}`}
      </p>

      {groups.length > 0 && (
        <div className="space-y-3 max-h-60 overflow-y-auto">
          {groups.map((g) => (
            <div key={g.classId}>
              <h5 className="text-xs font-semibold uppercase tracking-wider text-text-secondary mb-1.5">
                {g.className} · {g.students.length}
              </h5>
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
    </div>
  );
}
