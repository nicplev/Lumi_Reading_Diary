'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import {
  DndContext,
  closestCenter,
  PointerSensor,
  KeyboardSensor,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core';
import { SortableContext, rectSortingStrategy, useSortable, arrayMove } from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { Avatar } from '@/components/lumi/avatar';
import { useToast } from '@/components/lumi/toast';
import {
  useReadingGroups,
  useCreateReadingGroup,
  useUpdateReadingGroup,
  useDeleteReadingGroup,
  useReadingGroupStats,
  useReorderReadingGroups,
} from '@/lib/hooks/use-reading-groups';
import { useStudents } from '@/lib/hooks/use-students';
import { ReadingGroupOrganizer } from './reading-group-organizer';
import type { ReadingLevelOption, ReadingGroup, ReadingGroupStat } from '@/lib/types';

interface ReadingGroupsTabProps {
  classId: string;
  levelOptions: ReadingLevelOption[];
}

const GROUP_COLORS = [
  '#FF8698', '#D2EBBF', '#FF8B5A', '#BCE7F0',
  '#FFF6A4', '#FFAB91', '#CE93D8', '#80DEEA',
];

export function ReadingGroupsTab({ classId, levelOptions }: ReadingGroupsTabProps) {
  const { toast } = useToast();
  const { data: groups, isLoading } = useReadingGroups(classId);
  const { data: students } = useStudents({ classId });
  const { data: stats } = useReadingGroupStats(classId);
  const createGroup = useCreateReadingGroup();
  const updateGroup = useUpdateReadingGroup();
  const deleteGroup = useDeleteReadingGroup();
  const reorderGroups = useReorderReadingGroups();

  const [showCreate, setShowCreate] = useState(false);
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);
  const [deletingGroupId, setDeletingGroupId] = useState<string | null>(null);
  const [managingGroupId, setManagingGroupId] = useState<string | null>(null);
  const [reordering, setReordering] = useState(false);
  const [organizing, setOrganizing] = useState(false);
  const [order, setOrder] = useState<string[]>([]);

  // Create form state
  const [formName, setFormName] = useState('');
  const [formLevel, setFormLevel] = useState('');
  const [formColor, setFormColor] = useState(GROUP_COLORS[0]);
  const [formDescription, setFormDescription] = useState('');
  const [formTarget, setFormTarget] = useState('15');

  // Student assignment state
  const [assignedStudentIds, setAssignedStudentIds] = useState<string[]>([]);

  const statById = useMemo(
    () => new Map((stats ?? []).map((s) => [s.groupId, s])),
    [stats]
  );

  // Keep a local display order in sync with the (sortOrder-ordered) groups so
  // drag-reorder feels instant; persistence happens on drop.
  useEffect(() => {
    setOrder(groups ? groups.map((g) => g.id) : []);
  }, [groups]);

  // One-time reconcile: strip group studentIds that don't resolve to a current
  // class student (orphaned/stale data that otherwise renders as "Unknown").
  // Guarded on a non-empty roster so we never wipe members when students are
  // still loading or the roster came back empty.
  const reconciledRef = useRef<Set<string>>(new Set());
  useEffect(() => {
    if (!groups || !students || students.length === 0) return;
    const valid = new Set(students.map((s) => s.id));
    for (const g of groups) {
      if (reconciledRef.current.has(g.id)) continue;
      const cleaned = g.studentIds.filter((id) => valid.has(id));
      if (cleaned.length !== g.studentIds.length) {
        reconciledRef.current.add(g.id);
        updateGroup.mutate({ groupId: g.id, studentIds: cleaned });
      }
    }
  }, [groups, students, updateGroup]);

  const groupById = useMemo(() => new Map((groups ?? []).map((g) => [g.id, g])), [groups]);
  const orderedGroups = useMemo(
    () => order.map((id) => groupById.get(id)).filter((g): g is NonNullable<typeof g> => !!g),
    [order, groupById]
  );

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor)
  );

  const handleDragEnd = (event: DragEndEvent) => {
    const { active, over } = event;
    if (!over || active.id === over.id) return;
    const ids = orderedGroups.map((g) => g.id);
    const from = ids.indexOf(active.id as string);
    const to = ids.indexOf(over.id as string);
    if (from < 0 || to < 0) return;
    const next = arrayMove(ids, from, to);
    setOrder(next);
    reorderGroups.mutate(
      { classId, orderedIds: next },
      { onError: (e) => toast(e instanceof Error ? e.message : 'Failed to reorder', 'error') }
    );
  };

  const groupedStudentIds = new Set(groups?.flatMap((g) => g.studentIds) ?? []);
  const ungroupedStudents = students?.filter((s) => !groupedStudentIds.has(s.id)) ?? [];

  const resetForm = () => {
    setFormName('');
    setFormLevel('');
    setFormColor(GROUP_COLORS[0]);
    setFormDescription('');
    setFormTarget('15');
  };

  const handleCreate = async () => {
    try {
      await createGroup.mutateAsync({
        name: formName,
        classId,
        readingLevel: formLevel || undefined,
        color: formColor,
        description: formDescription || undefined,
        targetMinutes: parseInt(formTarget) || 15,
      });
      setShowCreate(false);
      resetForm();
      toast('Reading group created', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create group', 'error');
    }
  };

  const handleDelete = async () => {
    if (!deletingGroupId) return;
    try {
      await deleteGroup.mutateAsync({ groupId: deletingGroupId });
      setDeletingGroupId(null);
      toast('Reading group deleted', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete group', 'error');
    }
  };

  const openManageStudents = (groupId: string) => {
    const group = groups?.find((g) => g.id === groupId);
    setAssignedStudentIds(group?.studentIds ?? []);
    setManagingGroupId(groupId);
  };

  const handleSaveStudents = async () => {
    if (!managingGroupId) return;
    try {
      await updateGroup.mutateAsync({
        groupId: managingGroupId,
        studentIds: assignedStudentIds,
      });
      setManagingGroupId(null);
      toast('Students updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update students', 'error');
    }
  };

  if (isLoading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="bg-surface rounded-[var(--radius-lg)] shadow-card p-5 animate-pulse">
            <div className="h-5 bg-divider/60 rounded w-24 mb-3" />
            <div className="h-4 bg-divider/60 rounded w-16" />
          </div>
        ))}
      </div>
    );
  }

  if (organizing && groups && students) {
    return (
      <ReadingGroupOrganizer
        groups={groups.map((g) => ({ id: g.id, name: g.name, color: g.color ?? null, studentIds: g.studentIds }))}
        students={students.map((s) => ({
          id: s.id,
          firstName: s.firstName,
          lastName: s.lastName,
          characterId: s.characterId,
        }))}
        onExit={() => setOrganizing(false)}
      />
    );
  }

  return (
    <div>
      {ungroupedStudents.length > 0 && (
        <div className="mb-4 p-4 bg-soft-yellow/30 rounded-[var(--radius-md)] border border-soft-yellow">
          <p className="text-sm font-semibold text-charcoal">
            {ungroupedStudents.length} student{ungroupedStudents.length !== 1 ? 's' : ''} not in any group
          </p>
          <p className="text-xs text-text-secondary mt-0.5">
            {ungroupedStudents.map((s) => `${s.firstName} ${s.lastName}`).slice(0, 5).join(', ')}
            {ungroupedStudents.length > 5 && ` and ${ungroupedStudents.length - 5} more`}
          </p>
        </div>
      )}

      <div className="flex items-center justify-between gap-3 mb-4">
        <p className="text-sm text-text-secondary">
          {reordering ? 'Drag the groups into the order you want.' : ''}
        </p>
        <div className="flex items-center gap-2 shrink-0">
          {!reordering && groups && groups.length > 0 && students && students.length > 0 && (
            <Button variant="outline" onClick={() => setOrganizing(true)}>
              <Icon name="swap_horiz" size={16} className="mr-1.5" />
              Move Students
            </Button>
          )}
          {groups && groups.length > 1 && (
            <Button variant="outline" onClick={() => setReordering((r) => !r)}>
              <Icon name={reordering ? 'check' : 'swap_vert'} size={16} className="mr-1.5" />
              {reordering ? 'Done' : 'Reorder'}
            </Button>
          )}
          {!reordering && <Button onClick={() => setShowCreate(true)}>Create Group</Button>}
        </div>
      </div>

      {(!groups || groups.length === 0) ? (
        <EmptyState
          icon={<Icon name="library_books" size={40} />}
          title="No reading groups"
          description="Create reading groups to organize students by level."
          action={<Button onClick={() => setShowCreate(true)}>Create Group</Button>}
        />
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={handleDragEnd}>
          <SortableContext items={orderedGroups.map((g) => g.id)} strategy={rectSortingStrategy}>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 items-stretch">
              {orderedGroups.map((group) => (
                <GroupCard
                  key={group.id}
                  group={group}
                  stat={statById.get(group.id)}
                  students={students}
                  expanded={expandedGroup === group.id}
                  reordering={reordering}
                  onToggleExpand={() => setExpandedGroup(expandedGroup === group.id ? null : group.id)}
                  onManage={() => openManageStudents(group.id)}
                  onDelete={() => setDeletingGroupId(group.id)}
                />
              ))}
            </div>
          </SortableContext>
        </DndContext>
      )}

      {/* Create Group Modal */}
      <Modal
        open={showCreate}
        onClose={() => { setShowCreate(false); resetForm(); }}
        title="Create Reading Group"
        size="md"
        footer={
          <>
            <Button variant="outline" onClick={() => { setShowCreate(false); resetForm(); }}>Cancel</Button>
            <Button onClick={handleCreate} loading={createGroup.isPending} disabled={!formName}>Create</Button>
          </>
        }
      >
        <div className="space-y-4">
          <Input label="Group Name" value={formName} onChange={(e) => setFormName(e.target.value)} placeholder="e.g. Level B Readers" />
          <Input label="Description (optional)" value={formDescription} onChange={(e) => setFormDescription(e.target.value)} />
          <div>
            <label className="block text-sm font-semibold text-charcoal mb-1.5">Reading Level (optional)</label>
            <div className="flex flex-wrap gap-2">
              {levelOptions.slice(0, 16).map((opt) => (
                <button
                  key={opt.value}
                  onClick={() => setFormLevel(formLevel === opt.value ? '' : opt.value)}
                  className={`px-2 py-1 rounded-[var(--radius-sm)] text-xs font-bold ${
                    formLevel === opt.value ? 'ring-2 ring-rose-pink bg-rose-pink/10' : 'bg-background text-text-secondary'
                  }`}
                >
                  {opt.shortLabel}
                </button>
              ))}
            </div>
          </div>
          <div>
            <label className="block text-sm font-semibold text-charcoal mb-1.5">Color</label>
            <div className="flex gap-2">
              {GROUP_COLORS.map((color) => (
                <button
                  key={color}
                  onClick={() => setFormColor(color)}
                  className={`w-8 h-8 rounded-full ${formColor === color ? 'ring-2 ring-offset-2 ring-charcoal' : ''}`}
                  style={{ backgroundColor: color }}
                />
              ))}
            </div>
          </div>
          <Input label="Target Minutes" type="number" value={formTarget} onChange={(e) => setFormTarget(e.target.value)} min={1} />
        </div>
      </Modal>

      {/* Manage Students Modal */}
      <Modal
        open={!!managingGroupId}
        onClose={() => setManagingGroupId(null)}
        title="Manage Group Students"
        size="md"
        footer={
          <>
            <Button variant="outline" onClick={() => setManagingGroupId(null)}>Cancel</Button>
            <Button onClick={handleSaveStudents} loading={updateGroup.isPending}>Save</Button>
          </>
        }
      >
        <div className="max-h-80 overflow-y-auto space-y-2">
          {students?.map((s) => (
            <label key={s.id} className="flex items-center gap-3 p-2 rounded-[var(--radius-sm)] hover:bg-background cursor-pointer">
              <input
                type="checkbox"
                checked={assignedStudentIds.includes(s.id)}
                onChange={() =>
                  setAssignedStudentIds((prev) =>
                    prev.includes(s.id) ? prev.filter((id) => id !== s.id) : [...prev, s.id]
                  )
                }
                className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
              />
              <span className="text-sm text-charcoal font-semibold">{s.firstName} {s.lastName}</span>
              {s.currentReadingLevel && <ReadingLevelPill level={s.currentReadingLevel} size="sm" />}
            </label>
          ))}
        </div>
      </Modal>

      <ConfirmDialog
        open={!!deletingGroupId}
        onClose={() => setDeletingGroupId(null)}
        onConfirm={handleDelete}
        title="Delete Reading Group"
        description="Are you sure? Students will be ungrouped but not deleted."
        confirmLabel="Delete"
        loading={deleteGroup.isPending}
      />
    </div>
  );
}

function GroupCard({
  group,
  stat,
  students,
  expanded,
  reordering,
  onToggleExpand,
  onManage,
  onDelete,
}: {
  group: Pick<ReadingGroup, 'id' | 'name' | 'color' | 'readingLevel' | 'studentIds'>;
  stat: ReadingGroupStat | undefined;
  students: { id: string; firstName: string; lastName: string; characterId?: string }[] | undefined;
  expanded: boolean;
  reordering: boolean;
  onToggleExpand: () => void;
  onManage: () => void;
  onDelete: () => void;
}) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: group.id,
    disabled: !reordering,
  });
  const style: React.CSSProperties = { transform: CSS.Transform.toString(transform), transition };

  // Resolve member ids to current class students; unresolved ids (orphaned data)
  // are simply omitted rather than shown as "Unknown".
  const resolvedMembers = group.studentIds
    .map((sid) => students?.find((st) => st.id === sid))
    .filter((s): s is NonNullable<typeof s> => !!s);
  const memberCount = students ? resolvedMembers.length : group.studentIds.length;

  return (
    <div ref={setNodeRef} style={style} className={isDragging ? 'z-10' : ''}>
      <Card
        hover={!reordering}
        onClick={reordering ? undefined : onToggleExpand}
        className={`h-full ${reordering ? 'ring-1 ring-inset ring-rose-pink/30' : ''} ${
          isDragging ? 'shadow-card-hover' : ''
        }`}
      >
        <div>
          <div className="flex items-start justify-between mb-2 gap-2">
            <div className="flex items-center gap-1.5 min-w-0">
              {reordering && (
                <button
                  type="button"
                  className="cursor-grab active:cursor-grabbing touch-none text-text-secondary -ml-1"
                  aria-label="Drag to reorder"
                  {...attributes}
                  {...listeners}
                >
                  <Icon name="drag_indicator" size={18} />
                </button>
              )}
              {group.color && (
                <span
                  className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                  style={{ backgroundColor: group.color }}
                />
              )}
              <h3 className="font-bold text-charcoal truncate">{group.name}</h3>
            </div>
            <Badge variant="info">{memberCount}</Badge>
          </div>

          {group.readingLevel && <ReadingLevelPill level={group.readingLevel} colorHex={group.color} size="sm" />}

          {/* This-week stats strip */}
          {stat && (
            <div className="mt-2 flex flex-wrap gap-x-3 gap-y-0.5 text-xs text-text-secondary">
              <span>
                <span className="font-semibold text-charcoal">{stat.activeReaders}/{stat.totalStudents}</span> reading
              </span>
              <span>
                <span className="font-semibold text-charcoal">{stat.avgMinutes}</span> min avg
              </span>
              <span>
                <span className="font-semibold text-charcoal">{stat.studentsMetTarget}</span> met target
              </span>
            </div>
          )}

          {!reordering && expanded && (
            <div className="mt-3 pt-3 border-t border-divider">
              {stat && (stat.topReaderName || stat.needsSupportCount > 0) && (
                <div className="mb-3 space-y-1 text-xs">
                  {stat.topReaderName && (
                    <p className="text-text-secondary flex items-center gap-1.5">
                      <Icon name="star" size={14} className="text-warm-orange flex-shrink-0" />
                      <span>
                        Top reader: <span className="text-charcoal font-medium">{stat.topReaderName}</span> ({stat.topReaderMinutes} min)
                      </span>
                    </p>
                  )}
                  {stat.needsSupportCount > 0 && (
                    <p
                      className="text-text-secondary flex items-center gap-1.5"
                      title="Students who read on fewer than 3 days, met under half their target, or didn't read at all this week."
                    >
                      <Icon name="info" size={14} className="flex-shrink-0" />
                      <span>{stat.needsSupportCount} need attention this week</span>
                    </p>
                  )}
                </div>
              )}
              {resolvedMembers.length === 0 ? (
                <p className="text-xs text-text-secondary">No students assigned</p>
              ) : (
                <ul className="space-y-0.5 text-sm text-charcoal">
                  {resolvedMembers.map((s) => (
                    <li key={s.id}>
                      <Link
                        href={`/students/${s.id}`}
                        onClick={(e) => e.stopPropagation()}
                        className="flex items-center gap-2 rounded-[var(--radius-sm)] px-1 py-0.5 -mx-1 hover:bg-background transition-colors"
                      >
                        <Avatar name={`${s.firstName} ${s.lastName}`} characterId={s.characterId} size="xs" />
                        {s.firstName} {s.lastName}
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
              <div className="flex gap-2 mt-3">
                <Button size="sm" variant="outline" onClick={(e) => { e.stopPropagation(); onManage(); }}>
                  Manage Students
                </Button>
                <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); onDelete(); }}>
                  Delete
                </Button>
              </div>
            </div>
          )}
        </div>
      </Card>
    </div>
  );
}
