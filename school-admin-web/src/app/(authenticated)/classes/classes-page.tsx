'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { Tabs } from '@/components/lumi/tabs';
import { useToast } from '@/components/lumi/toast';
import { ClassFormModal } from './class-form-modal';
import { KanbanBoard } from './kanban-board';
import { useClasses, useCreateClass, useUpdateClass, useDeleteClass } from '@/lib/hooks/use-classes';
import type { SchoolClass } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };
type ViewMode = 'list' | 'board';

interface ClassesPageProps {
  teachers: { id: string; fullName: string }[];
  /** Admins get the full List/Board management view; teachers (only reaching
   *  this page when they have no class assigned) get a simple empty state. */
  isAdmin: boolean;
}

export function ClassesPage({ teachers, isAdmin }: ClassesPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const { data: classes, isLoading } = useClasses();
  const createClass = useCreateClass();
  const updateClass = useUpdateClass();
  const deleteClass = useDeleteClass();

  const [viewMode, setViewMode] = useState<ViewMode>('list');
  const [showCreate, setShowCreate] = useState(false);
  const [editingClass, setEditingClass] = useState<SerializedClass | null>(null);
  const [deletingClass, setDeletingClass] = useState<SerializedClass | null>(null);
  // Deep-link from the dashboard's "X classes without a teacher" attention row.
  const [noTeacherOnly, setNoTeacherOnly] = useState(false);
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get('filter') === 'no-teacher') {
      setNoTeacherOnly(true);
      setViewMode('list');
    }
  }, []);

  const teacherMap = new Map(teachers.map((t) => [t.id, t.fullName]));

  const visibleClasses = noTeacherOnly
    ? (classes ?? []).filter((c) => c.teacherIds.length === 0)
    : (classes ?? []);

  const columns: DataTableColumn<SerializedClass>[] = [
    {
      id: 'name',
      header: 'Name',
      accessorFn: (row) => row.name,
      cell: (val) => <span className="font-semibold">{val as string}</span>,
      sortable: true,
    },
    {
      id: 'yearLevel',
      header: 'Year Level',
      accessorFn: (row) => row.yearLevel ?? '',
      cell: (val) => val ? <Badge>{val as string}</Badge> : <span className="text-muted">-</span>,
      sortable: true,
    },
    {
      id: 'teachers',
      header: 'Teachers',
      accessorFn: (row) => row.teacherIds.map((id) => teacherMap.get(id) ?? 'Unknown').join(', '),
      cell: (val) => <span className="text-sm text-muted">{(val as string) || 'None assigned'}</span>,
    },
    {
      id: 'students',
      header: 'Students',
      accessorFn: (row) => row.studentIds.length,
      cell: (val) => <Badge variant="info">{val as number}</Badge>,
      sortable: true,
    },
    {
      id: 'actions',
      header: '',
      accessorFn: () => '',
      cell: (_, row) => (
        <div className="flex gap-1 justify-end" onClick={(e) => e.stopPropagation()}>
          <Button variant="ghost" size="sm" onClick={() => setEditingClass(row)}>
            Edit
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setDeletingClass(row)}>
            Delete
          </Button>
        </div>
      ),
      className: 'w-32',
    },
  ];

  const handleCreate = async (data: { name: string; yearLevel?: string; teacherIds: string[]; defaultMinutesTarget: number }) => {
    try {
      await createClass.mutateAsync(data);
      setShowCreate(false);
      toast('Class created successfully', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create class', 'error');
    }
  };

  const handleUpdate = async (data: { name: string; yearLevel?: string; teacherIds: string[]; defaultMinutesTarget: number }) => {
    if (!editingClass) return;
    try {
      await updateClass.mutateAsync({ classId: editingClass.id, ...data });
      setEditingClass(null);
      toast('Class updated successfully', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update class', 'error');
    }
  };

  const handleDelete = async () => {
    if (!deletingClass) return;
    try {
      await deleteClass.mutateAsync(deletingClass.id);
      setDeletingClass(null);
      toast('Class deleted successfully', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete class', 'error');
    }
  };

  if (!isAdmin) {
    return (
      <div>
        <PageHeader eyebrow="Class" title="Class" description="Your assigned class" />
        <EmptyState
          icon={<Icon name="school" size={40} />}
          title="No class assigned yet"
          description="Your school admin will assign you to a class. Check back soon."
        />
      </div>
    );
  }

  return (
    <div>
      <PageHeader
        eyebrow="Class"
        title="Classes"
        description="Manage your school's classes"
        action={<Button onClick={() => setShowCreate(true)}>Add Class</Button>}
      />

      <Tabs
        tabs={[
          { id: 'list', label: 'List' },
          { id: 'board', label: 'Board' },
        ]}
        activeTab={viewMode}
        onChange={(id) => setViewMode(id as ViewMode)}
      />

      {noTeacherOnly && (
        <div className="mb-4 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-section/10 text-sm font-semibold text-section-strong">
          <Icon name="filter_alt" size={16} />
          Showing classes without a teacher
          <button onClick={() => setNoTeacherOnly(false)} aria-label="Clear filter" className="hover:text-ink leading-none">
            <Icon name="close" size={16} />
          </button>
        </div>
      )}

      {viewMode === 'list' ? (
        <DataTable
          columns={columns}
          data={visibleClasses}
          loading={isLoading}
          onRowClick={(row) => router.push(`/classes/${row.id}`)}
          emptyState={
            <EmptyState
              icon={<Icon name="school" size={40} />}
              title={noTeacherOnly ? 'No classes without a teacher' : 'No classes yet'}
              description={noTeacherOnly ? 'Every class has a teacher assigned.' : 'Create your first class to get started.'}
              action={noTeacherOnly ? undefined : <Button onClick={() => setShowCreate(true)}>Add Class</Button>}
            />
          }
        />
      ) : (
        <KanbanBoard teachers={teachers} />
      )}

      <ClassFormModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        onSubmit={handleCreate}
        loading={createClass.isPending}
        teachers={teachers}
      />

      <ClassFormModal
        open={!!editingClass}
        onClose={() => setEditingClass(null)}
        onSubmit={handleUpdate}
        loading={updateClass.isPending}
        initialData={editingClass ?? undefined}
        teachers={teachers}
      />

      <ConfirmDialog
        open={!!deletingClass}
        onClose={() => setDeletingClass(null)}
        onConfirm={handleDelete}
        title="Delete Class"
        description={`Are you sure you want to delete "${deletingClass?.name}"? This will deactivate the class but student records will be preserved.`}
        confirmLabel="Delete"
        loading={deleteClass.isPending}
      />
    </div>
  );
}
