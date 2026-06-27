'use client';

import { useDroppable } from '@dnd-kit/core';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';

interface KanbanColumnProps {
  classId: string | null;
  className: string;
  yearLevel?: string;
  teacherNames?: string[];
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
  teacherNames,
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
      className={`w-[320px] min-w-[320px] flex-shrink-0 h-full flex flex-col rounded-[var(--radius-lg)] border border-rule bg-paper ${
        isUnassigned ? '' : ''
      }`}
    >
      {/* Header */}
      <div
        className={`px-4 py-3 border-b border-rule ${
          isUnassigned ? 'bg-cream rounded-t-[var(--radius-lg)]' : ''
        }`}
      >
        <div className="flex items-center gap-2">
          <span className="font-bold text-sm text-ink truncate">{className}</span>
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
        {!isUnassigned && (
          <p className="mt-1 text-xs text-muted truncate">
            {teacherNames && teacherNames.length > 0 ? teacherNames.join(', ') : 'No teacher assigned'}
          </p>
        )}
      </div>

      {/* Body */}
      <div
        ref={setNodeRef}
        className={`flex-1 overflow-y-auto p-2 space-y-1.5 min-h-[120px] transition-colors ${
          isOver ? 'border-2 border-dashed border-section bg-section/5 rounded-b-[var(--radius-lg)]' : ''
        }`}
      >
        {studentCount === 0 ? (
          <div className="flex items-center justify-center h-full">
            <span className="text-muted text-xs">No students</span>
          </div>
        ) : (
          children
        )}
      </div>

      {/* Footer */}
      <div className="px-3 py-2 border-t border-rule/50">
        <Button variant="ghost" size="sm" onClick={onAddStudent} className="w-full text-sm">
          + Add Student
        </Button>
      </div>
    </div>
  );
}
