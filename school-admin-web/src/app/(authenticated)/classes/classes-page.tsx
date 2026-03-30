'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { ClassFormModal } from './class-form-modal';
import { useClasses, useCreateClass, useUpdateClass, useDeleteClass } from '@/lib/hooks/use-classes';
import type { SchoolClass } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface ClassesPageProps {
  teachers: { id: string; fullName: string }[];
}

export function ClassesPage({ teachers }: ClassesPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const { data: classes, isLoading } = useClasses();
  const createClass = useCreateClass();
  const updateClass = useUpdateClass();
  const deleteClass = useDeleteClass();

  const [showCreate, setShowCreate] = useState(false);
  const [editingClass, setEditingClass] = useState<SerializedClass | null>(null);
  const [deletingClass, setDeletingClass] = useState<SerializedClass | null>(null);

  const teacherMap = new Map(teachers.map((t) => [t.id, t.fullName]));

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
      cell: (val) => val ? <Badge>{val as string}</Badge> : <span className="text-text-secondary">-</span>,
      sortable: true,
    },
    {
      id: 'teachers',
      header: 'Teachers',
      accessorFn: (row) => row.teacherIds.map((id) => teacherMap.get(id) ?? 'Unknown').join(', '),
      cell: (val) => <span className="text-sm text-text-secondary">{(val as string) || 'None assigned'}</span>,
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

  return (
    <div>
      <PageHeader
        title="Classes"
        description="Manage your school's classes"
        action={<Button onClick={() => setShowCreate(true)}>Add Class</Button>}
      />

      <DataTable
        columns={columns}
        data={classes ?? []}
        loading={isLoading}
        onRowClick={(row) => router.push(`/classes/${row.id}`)}
        emptyState={
          <EmptyState
            icon={<Icon name="school" size={40} />}
            title="No classes yet"
            description="Create your first class to get started."
            action={<Button onClick={() => setShowCreate(true)}>Add Class</Button>}
          />
        }
      />

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
