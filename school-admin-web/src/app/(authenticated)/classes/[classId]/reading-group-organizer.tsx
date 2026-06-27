'use client';

import { useMemo, useState } from 'react';
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  KeyboardSensor,
  useSensor,
  useSensors,
  useDraggable,
  useDroppable,
  closestCorners,
  type DragEndEvent,
  type DragStartEvent,
} from '@dnd-kit/core';
import { Button } from '@/components/lumi/button';
import { Avatar } from '@/components/lumi/avatar';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';
import { useUpdateReadingGroup } from '@/lib/hooks/use-reading-groups';
import { UnsavedChangesBar } from '../unsaved-changes-bar';

const UNGROUPED = 'ungrouped';

interface OrganizerStudent {
  id: string;
  firstName: string;
  lastName: string;
  characterId?: string;
}

interface OrganizerGroup {
  id: string;
  name: string;
  color: string | null;
  studentIds: string[];
}

/**
 * Kanban-style board (mirroring the admin class board) for dragging students
 * between reading groups. Changes are staged and committed together; only
 * groups whose membership actually changed are written, and orphaned ids (not
 * in the class roster) are dropped on save so stale data self-heals.
 */
export function ReadingGroupOrganizer({
  groups,
  students,
  onExit,
}: {
  groups: OrganizerGroup[];
  students: OrganizerStudent[];
  onExit: () => void;
}) {
  const { toast } = useToast();
  const updateGroup = useUpdateReadingGroup();
  const [saving, setSaving] = useState(false);
  const [moves, setMoves] = useState<Map<string, string>>(new Map());
  const [activeId, setActiveId] = useState<string | null>(null);

  const rosterIds = useMemo(() => new Set(students.map((s) => s.id)), [students]);
  const studentById = useMemo(() => new Map(students.map((s) => [s.id, s])), [students]);

  // Each student's starting column — first group containing them, else ungrouped.
  const initialColumnOf = useMemo(() => {
    const m = new Map<string, string>();
    for (const g of groups) {
      for (const sid of g.studentIds) {
        if (rosterIds.has(sid) && !m.has(sid)) m.set(sid, g.id);
      }
    }
    for (const s of students) if (!m.has(s.id)) m.set(s.id, UNGROUPED);
    return m;
  }, [groups, students, rosterIds]);

  const columnOf = (sid: string) => moves.get(sid) ?? initialColumnOf.get(sid) ?? UNGROUPED;
  const membersOf = (columnId: string) => students.filter((s) => columnOf(s.id) === columnId);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor)
  );

  const handleDragEnd = (e: DragEndEvent) => {
    setActiveId(null);
    const { active, over } = e;
    if (!over) return;
    const sid = active.id as string;
    const target = over.id as string;
    if (columnOf(sid) === target) return;
    setMoves((prev) => {
      const next = new Map(prev);
      if (target === (initialColumnOf.get(sid) ?? UNGROUPED)) next.delete(sid);
      else next.set(sid, target);
      return next;
    });
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const writes: Promise<unknown>[] = [];
      for (const g of groups) {
        // Start from the server list cleaned of orphans, then apply drag deltas.
        const set = new Set(g.studentIds.filter((id) => rosterIds.has(id)));
        for (const [sid, target] of moves) {
          const init = initialColumnOf.get(sid) ?? UNGROUPED;
          if (init === g.id && target !== g.id) set.delete(sid);
          if (target === g.id && init !== g.id) set.add(sid);
        }
        const newIds = [...set];
        const origIds = g.studentIds;
        const unchanged =
          newIds.length === origIds.length && newIds.every((id) => origIds.includes(id));
        if (!unchanged) {
          writes.push(updateGroup.mutateAsync({ groupId: g.id, studentIds: newIds }));
        }
      }
      await Promise.all(writes);
      toast(`${moves.size} change${moves.size !== 1 ? 's' : ''} saved`, 'success');
      setMoves(new Map());
      onExit();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Some changes failed to save', 'error');
    } finally {
      setSaving(false);
    }
  };

  const columns = [{ id: UNGROUPED, name: 'Ungrouped', color: null }, ...groups];

  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-4">
        <p className="text-sm text-muted">Drag students between groups, then save.</p>
        <Button variant="outline" onClick={onExit} disabled={saving}>
          <Icon name="check" size={16} className="mr-1.5" />
          Done
        </Button>
      </div>

      <DndContext
        sensors={sensors}
        collisionDetection={closestCorners}
        onDragStart={(e: DragStartEvent) => setActiveId(e.active.id as string)}
        onDragEnd={handleDragEnd}
        onDragCancel={() => setActiveId(null)}
      >
        <div className="flex gap-4 overflow-x-auto pb-24">
          {columns.map((col) => (
            <Column key={col.id} id={col.id} name={col.name} color={col.color} members={membersOf(col.id)} />
          ))}
        </div>
        <DragOverlay>
          {activeId && studentById.get(activeId) ? (
            <Chip student={studentById.get(activeId)!} overlay />
          ) : null}
        </DragOverlay>
      </DndContext>

      <UnsavedChangesBar
        changeCount={moves.size}
        onSave={handleSave}
        onDiscard={() => setMoves(new Map())}
        isSaving={saving}
      />
    </div>
  );
}

function Column({
  id,
  name,
  color,
  members,
}: {
  id: string;
  name: string;
  color: string | null;
  members: OrganizerStudent[];
}) {
  const { setNodeRef, isOver } = useDroppable({ id });
  return (
    <div
      ref={setNodeRef}
      className={`w-60 flex-shrink-0 rounded-[var(--radius-lg)] border p-3 transition-colors ${
        isOver ? 'border-section bg-section/5' : 'border-rule bg-paper'
      }`}
    >
      <div className="flex items-center gap-2 mb-2.5">
        {color && <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ backgroundColor: color }} />}
        <span className="font-bold text-ink text-sm truncate">{name}</span>
        <span className="ml-auto text-xs text-muted">{members.length}</span>
      </div>
      <div className="space-y-1.5 min-h-[64px]">
        {members.map((s) => (
          <Chip key={s.id} student={s} />
        ))}
        {members.length === 0 && (
          <p className="text-xs text-muted/60 py-4 text-center">Drop students here</p>
        )}
      </div>
    </div>
  );
}

function Chip({ student, overlay }: { student: OrganizerStudent; overlay?: boolean }) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({ id: student.id });
  const style = transform ? { transform: `translate3d(${transform.x}px, ${transform.y}px, 0)` } : undefined;
  return (
    <div
      ref={overlay ? undefined : setNodeRef}
      style={overlay ? undefined : style}
      {...(overlay ? {} : listeners)}
      {...(overlay ? {} : attributes)}
      className={`flex items-center gap-2 p-2 rounded-[var(--radius-md)] bg-cream border border-rule cursor-grab active:cursor-grabbing touch-none ${
        isDragging && !overlay ? 'opacity-40' : ''
      } ${overlay ? 'shadow-card-hover' : ''}`}
    >
      <Avatar
        name={`${student.firstName} ${student.lastName}`}
        characterId={student.characterId}
        size="sm"
        className="flex-shrink-0"
      />
      <span className="text-sm text-ink font-medium truncate">
        {student.firstName} {student.lastName}
      </span>
    </div>
  );
}
