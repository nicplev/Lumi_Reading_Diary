'use client';

import { useState, useMemo, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { SearchInput } from '@/components/lumi/search-input';
import { Select } from '@/components/lumi/select';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { KebabMenu } from '@/components/lumi/kebab-menu';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { StudentFormModal } from './student-form-modal';
import { AddStudentsModal } from './add-students-modal';
import { ResetCodeDevButton } from './reset-code-dev-button';
import {
  useStudents,
  useCreateStudent,
  useUpdateStudent,
  useDeleteStudent,
  useBulkDeleteStudents,
  useBulkUpdateEnrollmentStatus,
  useUpdateEnrollmentStatus,
} from '@/lib/hooks/use-students';
import type { SchoolClass, ReadingLevelOption, ReadingLevelSchema, EnrollmentStatus } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface StudentsPageProps {
  classes: SerializedClass[];
  levelOptions: ReadingLevelOption[];
  levelSchema: ReadingLevelSchema;
  devAccess: boolean;
}

type QuickFilter = 'all' | 'has-parent' | 'no-parent';
type EnrollmentFilter = 'all' | 'subscribed' | 'not-subscribed';

const PAGE_SIZE_OPTIONS = [10, 20, 50, 100];

export function StudentsPage({ classes, levelOptions, levelSchema, devAccess }: StudentsPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const { data: students, isLoading } = useStudents();
  const createStudent = useCreateStudent();
  const updateStudent = useUpdateStudent();
  const deleteStudent = useDeleteStudent();
  const bulkDeleteStudents = useBulkDeleteStudents();
  const bulkUpdateEnrollment = useBulkUpdateEnrollmentStatus();
  const updateEnrollment = useUpdateEnrollmentStatus();

  const [search, setSearch] = useState('');
  const [classFilter, setClassFilter] = useState<string[]>([]);
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('all');
  const [enrollmentFilter, setEnrollmentFilter] = useState<EnrollmentFilter>('all');
  // Dashboard "Attention required" rows deep-link here with ?filter=… — apply it
  // once on mount as a dismissible chip, independent of the regular filters.
  const [deepFilter, setDeepFilter] = useState<'unassigned' | 'no-guardian' | null>(null);
  useEffect(() => {
    const f = new URLSearchParams(window.location.search).get('filter');
    if (f === 'unassigned' || f === 'no-guardian') setDeepFilter(f);
  }, []);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showAdd, setShowAdd] = useState(false);
  const [pageSize, setPageSize] = useState(20);

  type StudentRow = NonNullable<typeof students>[number];
  const [editingStudent, setEditingStudent] = useState<StudentRow | null>(null);
  const [deletingStudent, setDeletingStudent] = useState<StudentRow | null>(null);
  const [showBulkDeleteConfirm, setShowBulkDeleteConfirm] = useState(false);

  const classMap = new Map(classes.map((c) => [c.id, c.name]));

  const filtered = useMemo(() => {
    if (!students) return [];
    let list = [...students];

    if (deepFilter === 'unassigned') {
      list = list.filter((s) => !s.classId);
    } else if (deepFilter === 'no-guardian') {
      list = list.filter((s) => s.parentIds.length === 0);
    }

    if (classFilter.length > 0) {
      list = list.filter((s) => classFilter.includes(s.classId));
    }

    if (quickFilter === 'has-parent') {
      list = list.filter((s) => s.parentIds.length > 0);
    } else if (quickFilter === 'no-parent') {
      list = list.filter((s) => s.parentIds.length === 0);
    }

    if (enrollmentFilter === 'subscribed') {
      list = list.filter((s) => s.enrollmentStatus === 'book_pack' || s.enrollmentStatus === 'direct_purchase');
    } else if (enrollmentFilter === 'not-subscribed') {
      list = list.filter((s) => !s.enrollmentStatus || s.enrollmentStatus === 'not_enrolled');
    }

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (s) =>
          `${s.firstName} ${s.lastName}`.toLowerCase().includes(q) ||
          s.studentId?.toLowerCase().includes(q)
      );
    }

    return list;
  }, [students, search, classFilter, quickFilter, enrollmentFilter, deepFilter]);

  const toggleSelected = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const allFilteredSelected = filtered.length > 0 && selectedIds.size === filtered.length;
  const someFilteredSelected = selectedIds.size > 0 && !allFilteredSelected;

  const toggleSelectAll = () => {
    if (allFilteredSelected) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map((s) => s.id)));
    }
  };

  const handleSingleEnrollment = async (
    student: StudentRow,
    status: EnrollmentStatus,
  ) => {
    try {
      await updateEnrollment.mutateAsync({ studentId: student.id, enrollmentStatus: status });
      const label =
        status === 'book_pack' ? 'Subscribed' :
        status === 'direct_purchase' ? 'Subscribed (Direct)' : 'Not Subscribed';
      toast(`${student.firstName} marked ${label}`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update status', 'error');
    }
  };

  const handleBulkEnrollment = async (status: EnrollmentStatus) => {
    try {
      await bulkUpdateEnrollment.mutateAsync({
        studentIds: Array.from(selectedIds),
        enrollmentStatus: status,
      });
      const count = selectedIds.size;
      setSelectedIds(new Set());
      toast(`Updated ${count} students`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update', 'error');
    }
  };

  const handleBulkDelete = async () => {
    try {
      const ids = Array.from(selectedIds);
      const result = await bulkDeleteStudents.mutateAsync({ studentIds: ids });
      setSelectedIds(new Set());
      setShowBulkDeleteConfirm(false);
      toast(`Deleted ${result.count} students`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete', 'error');
    }
  };

  const handleDelete = async () => {
    if (!deletingStudent) return;
    try {
      await deleteStudent.mutateAsync(deletingStudent.id);
      setDeletingStudent(null);
      toast('Student deleted', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete student', 'error');
    }
  };

  const handleEdit = async (data: { studentId?: string; firstName: string; lastName: string; classId: string; dateOfBirth?: string; currentReadingLevel?: string; parentEmail?: string }) => {
    if (!editingStudent) return;
    try {
      await updateStudent.mutateAsync({
        id: editingStudent.id,
        studentId: data.studentId,
        firstName: data.firstName,
        lastName: data.lastName,
        classId: data.classId,
        currentReadingLevel: data.currentReadingLevel,
        parentEmail: data.parentEmail,
      });
      setEditingStudent(null);
      toast('Student updated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update student', 'error');
    }
  };

  const allColumns: DataTableColumn<StudentRow>[] = [
    {
      id: 'name',
      header: 'Name',
      accessorFn: (row) => `${row.firstName} ${row.lastName}`,
      cell: (val) => (
        <div className="flex items-center gap-3">
          <Avatar name={val as string} size="sm" />
          <span className="font-semibold">{val as string}</span>
        </div>
      ),
      sortable: true,
    },
    {
      id: 'studentId',
      header: 'Student ID',
      accessorFn: (row) => row.studentId ?? '',
      cell: (val) => <span className="text-muted">{(val as string) || '-'}</span>,
      sortable: true,
    },
    {
      id: 'class',
      header: 'Class',
      accessorFn: (row) => classMap.get(row.classId) ?? '',
      cell: (val) => <Badge>{val as string}</Badge>,
      sortable: true,
    },
    {
      id: 'level',
      header: 'Level',
      accessorFn: (row) => row.currentReadingLevel ?? '',
      cell: (val) => <ReadingLevelPill level={val as string} size="sm" />,
      sortable: true,
    },
    {
      id: 'parent',
      header: 'Parent/Guardian',
      accessorFn: (row) => row.parentIds.length > 0,
      cell: (val) =>
        val ? <Badge variant="success">Linked</Badge> : <Badge variant="default">No parent</Badge>,
    },
    {
      id: 'enrollment',
      header: 'Status',
      accessorFn: (row) => row.enrollmentStatus ?? 'not_enrolled',
      cell: (_val, row) => {
        // Read-only at a glance. Subscription changes are an exception-only
        // action (mid-year revoke, refund, correction) — they live in the row's
        // ⋮ menu and the bulk bar, not as an always-on inline editor. Onboarding
        // handles the start-of-year flow; Rollover handles the annual reset.
        const subscribed =
          row.enrollmentStatus === 'book_pack' || row.enrollmentStatus === 'direct_purchase';
        return (
          <span className="inline-flex items-center gap-1.5">
            <Badge variant={subscribed ? 'success' : 'error'}>
              {subscribed ? 'Subscribed' : 'Not Subscribed'}
            </Badge>
            {row.enrollmentStatus === 'direct_purchase' && <Badge variant="info">Direct</Badge>}
          </span>
        );
      },
      sortable: true,
    },
    {
      id: 'parentEmail',
      header: 'Parent Email',
      accessorFn: (row) => row.parentEmail ?? '',
      cell: (val) => <span className="text-sm text-muted">{(val as string) || '-'}</span>,
    },
  ];

  const baseColumns = levelSchema === 'none'
    ? allColumns.filter((col) => col.id !== 'level')
    : allColumns;

  const columns: DataTableColumn<StudentRow>[] = [
    {
      id: 'select',
      header: (
        <input
          type="checkbox"
          aria-label="Select all students"
          checked={allFilteredSelected}
          ref={(el) => {
            if (el) el.indeterminate = someFilteredSelected;
          }}
          onChange={toggleSelectAll}
          onClick={(e) => e.stopPropagation()}
          className="accent-section cursor-pointer"
        />
      ),
      accessorFn: () => null,
      cell: (_val, row) => (
        <input
          type="checkbox"
          checked={selectedIds.has(row.id)}
          onChange={(e) => { e.stopPropagation(); toggleSelected(row.id); }}
          onClick={(e) => e.stopPropagation()}
          className="accent-section"
        />
      ),
      className: 'w-10',
    },
    ...baseColumns,
    {
      id: 'actions',
      header: '',
      accessorFn: () => null,
      cell: (_val, row) => (
        <div className="flex justify-end">
          <KebabMenu
            items={[
              { label: 'Mark Subscribed', onClick: () => handleSingleEnrollment(row, 'book_pack') },
              { label: 'Mark Subscribed (Direct)', onClick: () => handleSingleEnrollment(row, 'direct_purchase') },
              { label: 'Mark Not Subscribed', onClick: () => handleSingleEnrollment(row, 'not_enrolled') },
              { label: 'Edit', onClick: () => setEditingStudent(row) },
              { label: 'Delete', onClick: () => setDeletingStudent(row), variant: 'danger' },
            ]}
          />
        </div>
      ),
      className: 'w-12 text-right',
    },
  ];

  const handleCreate = async (data: { studentId?: string; firstName: string; lastName: string; classId: string; dateOfBirth?: string; currentReadingLevel?: string; parentEmail?: string }) => {
    try {
      await createStudent.mutateAsync(data);
      setShowAdd(false);
      toast('Student created successfully', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create student', 'error');
    }
  };

  return (
    <div>
      <PageHeader
        eyebrow="Students"
        title="Students"
        description="Manage students across your school"
        action={
          <div className="flex gap-2 items-center">
            <ResetCodeDevButton visible={devAccess} />
            <Button onClick={() => setShowAdd(true)}>Add Students</Button>
          </div>
        }
      />

      {/* Filters — compact dropdowns so they don't dominate the page */}
      <div className="flex flex-col sm:flex-row sm:items-center gap-3 mb-6">
        <div className="flex-1">
          <SearchInput value={search} onChange={setSearch} placeholder="Search by name or student ID..." />
        </div>
        <div className="sm:w-52 shrink-0">
          <Select
            options={[
              { value: 'all', label: 'All classes' },
              ...classes.map((c) => ({
                value: c.id,
                label: `${c.name || c.yearLevel || 'Unnamed Class'} (${students?.filter((s) => s.classId === c.id).length ?? 0})`,
              })),
            ]}
            value={classFilter[0] ?? 'all'}
            onChange={(v) => setClassFilter(v === 'all' ? [] : [v])}
          />
        </div>
        <div className="sm:w-44 shrink-0">
          <Select
            options={[
              { value: 'all', label: 'All statuses' },
              { value: 'subscribed', label: 'Subscribed' },
              { value: 'not-subscribed', label: 'Not Subscribed' },
            ]}
            value={enrollmentFilter}
            onChange={(v) => setEnrollmentFilter(v as EnrollmentFilter)}
          />
        </div>
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex flex-wrap items-center gap-3 mb-4 p-3 bg-section/5 border border-section/20 rounded-[var(--radius-lg)]">
          <input
            type="checkbox"
            checked={allFilteredSelected}
            onChange={toggleSelectAll}
            className="accent-section"
          />
          <span className="text-sm font-semibold text-ink">{selectedIds.size} selected</span>
          <div className="flex flex-wrap gap-2 ml-auto">
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('book_pack')}>
              Mark Subscribed
            </Button>
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('direct_purchase')}>
              Mark Subscribed (Direct)
            </Button>
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('not_enrolled')}>
              Mark Not Subscribed
            </Button>
            <Button variant="danger" size="sm" onClick={() => setShowBulkDeleteConfirm(true)}>
              Delete
            </Button>
            <Button variant="outline" size="sm" onClick={() => setSelectedIds(new Set())}>
              Clear
            </Button>
          </div>
        </div>
      )}

      {deepFilter && (
        <div className="mb-4 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-section/10 text-sm font-semibold text-section-strong">
          <Icon name="filter_alt" size={16} />
          {deepFilter === 'unassigned' ? 'Showing unassigned students' : 'Showing students with no guardian'}
          <button onClick={() => setDeepFilter(null)} aria-label="Clear filter" className="hover:text-ink leading-none">
            <Icon name="close" size={16} />
          </button>
        </div>
      )}

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        pageSize={pageSize}
        pageSizeOptions={PAGE_SIZE_OPTIONS}
        onPageSizeChange={setPageSize}
        onRowClick={(row) => router.push(`/students/${row.id}`)}
        emptyState={
          <EmptyState
            icon={<Icon name="person" size={40} />}
            title="No students found"
            description={search || classFilter.length > 0 ? 'Try adjusting your filters.' : 'Add your first student to get started.'}
            action={!search && classFilter.length === 0 ? <Button onClick={() => setShowAdd(true)}>Add Students</Button> : undefined}
          />
        }
      />

      <AddStudentsModal
        open={showAdd}
        onClose={() => setShowAdd(false)}
        onSubmitManual={handleCreate}
        creating={createStudent.isPending}
        classes={classes}
        levelOptions={levelOptions}
      />

      <StudentFormModal
        open={!!editingStudent}
        onClose={() => setEditingStudent(null)}
        onSubmit={handleEdit}
        loading={updateStudent.isPending}
        classes={classes}
        levelOptions={levelOptions}
        initialData={editingStudent ? {
          studentId: editingStudent.studentId ?? '',
          firstName: editingStudent.firstName,
          lastName: editingStudent.lastName,
          classId: editingStudent.classId,
          dateOfBirth: editingStudent.dateOfBirth ? editingStudent.dateOfBirth.split('T')[0] : '',
          currentReadingLevel: editingStudent.currentReadingLevel ?? '',
          parentEmail: editingStudent.parentEmail ?? '',
        } : undefined}
      />

      <ConfirmDialog
        open={!!deletingStudent}
        onClose={() => setDeletingStudent(null)}
        onConfirm={handleDelete}
        title="Delete Student"
        description={deletingStudent ? `Permanently delete ${deletingStudent.firstName} ${deletingStudent.lastName}? This cannot be undone.` : ''}
        confirmLabel="Delete"
        variant="danger"
        loading={deleteStudent.isPending}
      />

      <ConfirmDialog
        open={showBulkDeleteConfirm}
        onClose={() => setShowBulkDeleteConfirm(false)}
        onConfirm={handleBulkDelete}
        title={`Delete ${selectedIds.size} students`}
        description={`Permanently delete ${selectedIds.size} selected students? This cannot be undone.`}
        confirmLabel="Delete"
        variant="danger"
        loading={bulkDeleteStudents.isPending}
      />

    </div>
  );
}
