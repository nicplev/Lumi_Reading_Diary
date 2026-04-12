'use client';

import { useDroppable } from '@dnd-kit/core';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';

interface KanbanColumnProps {
  classId: string | null;
  className: string;
  yearLevel?: string;
  studentCount: number;
  children: React.ReactNode;
  isOver: boolean;
  onAddStudent: () => void;
  onEditClass?: () => void;
}

export function KanbanColumn({
  classId,
  className,
  yearLevel,
  studentCount,
  children,
  isOver,
  onAddStudent,
  onEditClass,
}: KanbanColumnProps) {
  const isUnassigned = classId === null;
  const droppableId = classId ?? 'unassigned';

  const { setNodeRef } = useDroppable({ id: droppableId });

  return (
    <div
      className={`w-[320px] min-w-[320px] flex-shrink-0 h-full flex flex-col rounded-[var(--radius-lg)] border border-divider bg-surface ${
        isUnassigned ? '' : ''
      }`}
    >
      {/* Header */}
      <div
        className={`px-4 py-3 border-b border-divider flex items-center gap-2 ${
          isUnassigned ? 'bg-background rounded-t-[var(--radius-lg)]' : ''
        }`}
      >
        <span className="font-bold text-sm text-charcoal truncate">{className}</span>
        {yearLevel && <Badge>{yearLevel}</Badge>}
        <Badge variant="info">{studentCount}</Badge>
        <div className="flex-1" />
        {onEditClass && (
          <Button variant="ghost" size="sm" onClick={onEditClass} className="!px-1.5 !py-1">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path
                d="M11.33 2.67a1.41 1.41 0 0 1 2 2L5.78 12.22l-2.67.67.67-2.67 7.55-7.55Z"
                stroke="currentColor"
                strokeWidth="1.3"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </Button>
        )}
      </div>

      {/* Body */}
      <div
        ref={setNodeRef}
        className={`flex-1 overflow-y-auto p-2 space-y-1.5 min-h-[120px] transition-colors ${
          isOver ? 'border-2 border-dashed border-rose-pink bg-rose-pink/5 rounded-b-[var(--radius-lg)]' : ''
        }`}
      >
        {studentCount === 0 ? (
          <div className="flex items-center justify-center h-full">
            <span className="text-text-secondary text-xs">No students</span>
          </div>
        ) : (
          children
        )}
      </div>

      {/* Footer */}
      <div className="px-3 py-2 border-t border-divider/50">
        <Button variant="ghost" size="sm" onClick={onAddStudent} className="w-full text-sm">
          + Add Student
        </Button>
      </div>
    </div>
  );
}
