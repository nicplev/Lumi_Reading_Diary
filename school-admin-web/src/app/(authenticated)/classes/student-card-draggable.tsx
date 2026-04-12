'use client';

import { useDraggable } from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';
import { Avatar } from '@/components/lumi/avatar';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';

interface StudentCardDraggableProps {
  student: {
    id: string;
    firstName: string;
    lastName: string;
    currentReadingLevel?: string;
  };
  classId: string | null;
  isPending?: boolean;
  dimmed?: boolean;
  showReadingLevel?: boolean;
  onRemove?: () => void;
}

export function StudentCardDraggable({ student, classId, isPending = false, dimmed = false, showReadingLevel = true, onRemove }: StudentCardDraggableProps) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: student.id,
    data: { student, classId },
  });

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.4 : dimmed ? 0.3 : 1,
  };

  const fullName = `${student.firstName} ${student.lastName}`;

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...listeners}
      {...attributes}
      className={`group relative flex items-center gap-2.5 h-14 bg-surface rounded-[var(--radius-md)] px-3 py-2 transition-all ${
        isPending
          ? 'border-2 border-dashed border-orange-400/60 bg-orange-50/60'
          : 'border border-divider/50'
      } ${isDragging ? 'cursor-grabbing shadow-md' : 'cursor-grab hover:shadow-card'}`}
    >
      {isPending && (
        <span className="absolute top-1 left-1 w-1.5 h-1.5 rounded-full bg-orange-400" />
      )}
      <Avatar name={fullName} size="sm" />
      <span className="text-sm font-bold text-charcoal truncate flex-1">{fullName}</span>
      {showReadingLevel && student.currentReadingLevel && (
        <ReadingLevelPill level={student.currentReadingLevel} size="sm" />
      )}
      {onRemove && (
        <button
          onClick={(e) => {
            e.stopPropagation();
            onRemove();
          }}
          className="absolute -top-1.5 -right-1.5 hidden group-hover:flex items-center justify-center w-5 h-5 rounded-full bg-error text-white text-xs shadow-sm hover:bg-error/90 transition-colors"
        >
          <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
            <path d="M8 2L2 8M2 2l6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      )}
    </div>
  );
}
