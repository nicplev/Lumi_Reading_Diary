'use client';

import { useState } from 'react';
import { Card } from '@/components/lumi/card';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Modal } from '@/components/lumi/modal';
import { Input } from '@/components/lumi/input';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';
import {
  useReadingGroups,
  useCreateReadingGroup,
  useUpdateReadingGroup,
  useDeleteReadingGroup,
} from '@/lib/hooks/use-reading-groups';
import { useStudents } from '@/lib/hooks/use-students';
import type { ReadingLevelOption } from '@/lib/types';

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
  const createGroup = useCreateReadingGroup();
  const updateGroup = useUpdateReadingGroup();
  const deleteGroup = useDeleteReadingGroup();

  const [showCreate, setShowCreate] = useState(false);
  const [expandedGroup, setExpandedGroup] = useState<string | null>(null);
  const [deletingGroupId, setDeletingGroupId] = useState<string | null>(null);
  const [managingGroupId, setManagingGroupId] = useState<string | null>(null);

  // Create form state
  const [formName, setFormName] = useState('');
  const [formLevel, setFormLevel] = useState('');
  const [formColor, setFormColor] = useState(GROUP_COLORS[0]);
  const [formDescription, setFormDescription] = useState('');
  const [formTarget, setFormTarget] = useState('15');

  // Student assignment state
  const [assignedStudentIds, setAssignedStudentIds] = useState<string[]>([]);

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

      <div className="flex justify-end mb-4">
        <Button onClick={() => setShowCreate(true)}>Create Group</Button>
      </div>

      {(!groups || groups.length === 0) ? (
        <EmptyState
          icon={<Icon name="library_books" size={40} />}
          title="No reading groups"
          description="Create reading groups to organize students by level."
          action={<Button onClick={() => setShowCreate(true)}>Create Group</Button>}
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {groups.map((group) => (
            <Card
              key={group.id}
              hover
              onClick={() => setExpandedGroup(expandedGroup === group.id ? null : group.id)}
              className="relative overflow-hidden"
            >
              <div
                className="absolute top-0 left-0 w-1.5 h-full"
                style={{ backgroundColor: group.color || '#E5E7EB' }}
              />
              <div className="pl-3">
                <div className="flex items-start justify-between mb-2">
                  <h3 className="font-bold text-charcoal">{group.name}</h3>
                  <Badge variant="info">{group.studentIds.length}</Badge>
                </div>
                {group.readingLevel && (
                  <ReadingLevelPill level={group.readingLevel} colorHex={group.color} size="sm" />
                )}
                {expandedGroup === group.id && (
                  <div className="mt-3 pt-3 border-t border-divider">
                    {group.studentIds.length === 0 ? (
                      <p className="text-xs text-text-secondary">No students assigned</p>
                    ) : (
                      <ul className="space-y-1 text-sm text-charcoal">
                        {group.studentIds.map((sid) => {
                          const s = students?.find((st) => st.id === sid);
                          return (
                            <li key={sid}>
                              {s ? `${s.firstName} ${s.lastName}` : 'Unknown'}
                            </li>
                          );
                        })}
                      </ul>
                    )}
                    <div className="flex gap-2 mt-3">
                      <Button size="sm" variant="outline" onClick={(e) => { e.stopPropagation(); openManageStudents(group.id); }}>
                        Manage Students
                      </Button>
                      <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeletingGroupId(group.id); }}>
                        Delete
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            </Card>
          ))}
        </div>
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
