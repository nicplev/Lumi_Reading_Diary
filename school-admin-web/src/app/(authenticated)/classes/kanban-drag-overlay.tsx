'use client';

import { DragOverlay } from '@dnd-kit/core';
import { Avatar } from '@/components/lumi/avatar';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';

interface KanbanDragOverlayProps {
  activeStudent: {
    id: string;
    firstName: string;
    lastName: string;
    currentReadingLevel?: string;
  } | null;
}

export function KanbanDragOverlay({ activeStudent }: KanbanDragOverlayProps) {
  return (
    <DragOverlay>
      {activeStudent ? (
        <div className="flex items-center gap-2.5 h-14 bg-surface rounded-[var(--radius-md)] border border-rose-pink/30 px-3 py-2 shadow-lg scale-[1.03] rotate-[2deg]">
          <Avatar name={`${activeStudent.firstName} ${activeStudent.lastName}`} size="sm" />
          <span className="text-sm font-bold text-charcoal truncate flex-1">
            {activeStudent.firstName} {activeStudent.lastName}
          </span>
          {activeStudent.currentReadingLevel && (
            <ReadingLevelPill level={activeStudent.currentReadingLevel} size="sm" />
          )}
        </div>
      ) : null}
    </DragOverlay>
  );
}
