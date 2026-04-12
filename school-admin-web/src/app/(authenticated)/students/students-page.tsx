'use client';

import { useState, useMemo } from 'react';
import { useRouter } from 'next/navigation';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { SearchInput } from '@/components/lumi/search-input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Avatar } from '@/components/lumi/avatar';
import { Badge } from '@/components/lumi/badge';
import { ReadingLevelPill } from '@/components/lumi/reading-level-pill';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';
import { StudentFormModal } from './student-form-modal';
import { CSVImportDialog } from './csv-import-dialog';
import { useStudents, useCreateStudent, useBulkUpdateEnrollmentStatus } from '@/lib/hooks/use-students';
import type { SchoolClass, ReadingLevelOption, ReadingLevelSchema, EnrollmentStatus } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface StudentsPageProps {
  classes: SerializedClass[];
  levelOptions: ReadingLevelOption[];
  levelSchema: ReadingLevelSchema;
}

type QuickFilter = 'all' | 'has-parent' | 'no-parent';
type EnrollmentFilter = 'all' | 'enrolled' | 'not-enrolled' | 'pending';

const enrollmentBadge: Record<string, { label: string; variant: 'success' | 'info' | 'error' | 'warning' }> = {
  book_pack: { label: 'Confirmed', variant: 'success' },
  direct_purchase: { label: 'Confirmed (Direct)', variant: 'info' },
  not_enrolled: { label: 'Not Confirmed', variant: 'error' },
  pending: { label: 'Pending', variant: 'warning' },
};

export function StudentsPage({ classes, levelOptions, levelSchema }: StudentsPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const { data: students, isLoading } = useStudents();
  const createStudent = useCreateStudent();
  const bulkUpdateEnrollment = useBulkUpdateEnrollmentStatus();

  const [search, setSearch] = useState('');
  const [classFilter, setClassFilter] = useState<string[]>([]);
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('all');
  const [enrollmentFilter, setEnrollmentFilter] = useState<EnrollmentFilter>('all');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showCreate, setShowCreate] = useState(false);
  const [showImport, setShowImport] = useState(false);

  const classMap = new Map(classes.map((c) => [c.id, c.name]));

  const filtered = useMemo(() => {
    if (!students) return [];
    let list = [...students];

    if (classFilter.length > 0) {
      list = list.filter((s) => classFilter.includes(s.classId));
    }

    if (quickFilter === 'has-parent') {
      list = list.filter((s) => s.parentIds.length > 0);
    } else if (quickFilter === 'no-parent') {
      list = list.filter((s) => s.parentIds.length === 0);
    }

    if (enrollmentFilter === 'enrolled') {
      list = list.filter((s) => s.enrollmentStatus === 'book_pack' || s.enrollmentStatus === 'direct_purchase');
    } else if (enrollmentFilter === 'not-enrolled') {
      list = list.filter((s) => s.enrollmentStatus === 'not_enrolled');
    } else if (enrollmentFilter === 'pending') {
      list = list.filter((s) => !s.enrollmentStatus || s.enrollmentStatus === 'pending');
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
  }, [students, search, classFilter, quickFilter, enrollmentFilter]);

  const toggleSelected = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedIds.size === filtered.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map((s) => s.id)));
    }
  };

  const handleBulkEnrollment = async (status: EnrollmentStatus) => {
    try {
      await bulkUpdateEnrollment.mutateAsync({
        studentIds: Array.from(selectedIds),
        enrollmentStatus: status,
      });
      setSelectedIds(new Set());
      toast(`Updated ${selectedIds.size} students`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update', 'error');
    }
  };

  const allColumns: DataTableColumn<(typeof filtered)[0]>[] = [
    {
      id: 'name',
      header: 'Name',
      accessorFn: (row) => `${row.firstName} ${row.lastName}`,
      cell: (val, row) => (
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
      cell: (val) => <span className="text-text-secondary">{(val as string) || '-'}</span>,
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
      accessorFn: (row) => row.enrollmentStatus ?? 'pending',
      cell: (val) => {
        const info = enrollmentBadge[val as string] ?? enrollmentBadge.pending;
        return <Badge variant={info.variant}>{info.label}</Badge>;
      },
      sortable: true,
    },
    {
      id: 'parentEmail',
      header: 'Parent Email',
      accessorFn: (row) => row.parentEmail ?? '',
      cell: (val) => <span className="text-sm text-text-secondary">{(val as string) || '-'}</span>,
    },
  ];

  const columns = levelSchema === 'none'
    ? allColumns.filter((col) => col.id !== 'level')
    : allColumns;

  const handleCreate = async (data: { studentId?: string; firstName: string; lastName: string; classId: string; dateOfBirth?: string; currentReadingLevel?: string }) => {
    try {
      await createStudent.mutateAsync(data);
      setShowCreate(false);
      toast('Student created successfully', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to create student', 'error');
    }
  };

  return (
    <div>
      <PageHeader
        title="Students"
        description="Manage students across your school"
        action={
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => setShowImport(true)}>Import CSV</Button>
            <Button onClick={() => setShowCreate(true)}>Add Student</Button>
          </div>
        }
      />

      {/* Filters */}
      <div className="space-y-3 mb-6">
        <div className="flex flex-wrap gap-2">
          {classes.map((c) => (
            <FilterChip
              key={c.id}
              label={c.name || c.yearLevel || 'Unnamed Class'}
              selected={classFilter.includes(c.id)}
              count={students?.filter((s) => s.classId === c.id).length}
              onClick={() =>
                setClassFilter((prev) =>
                  prev.includes(c.id) ? prev.filter((id) => id !== c.id) : [...prev, c.id]
                )
              }
            />
          ))}
        </div>
        <div className="flex flex-wrap gap-2">
          {(['all', 'enrolled', 'not-enrolled', 'pending'] as const).map((filter) => (
            <FilterChip
              key={filter}
              label={
                filter === 'all' ? 'All Status' :
                filter === 'enrolled' ? 'Confirmed' :
                filter === 'not-enrolled' ? 'Not Confirmed' : 'Pending'
              }
              selected={enrollmentFilter === filter}
              onClick={() => setEnrollmentFilter(filter)}
            />
          ))}
        </div>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by name or student ID..." />
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 p-3 bg-rose-pink/5 border border-rose-pink/20 rounded-[var(--radius-lg)]">
          <input
            type="checkbox"
            checked={selectedIds.size === filtered.length}
            onChange={toggleSelectAll}
            className="accent-rose-pink"
          />
          <span className="text-sm font-semibold text-charcoal">{selectedIds.size} selected</span>
          <div className="flex gap-2 ml-auto">
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('book_pack')}>
              Mark Confirmed
            </Button>
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('not_enrolled')}>
              Mark Not Confirmed
            </Button>
            <Button variant="outline" size="sm" onClick={() => handleBulkEnrollment('direct_purchase')}>
              Mark Confirmed (Direct)
            </Button>
            <Button variant="outline" size="sm" onClick={() => setSelectedIds(new Set())}>
              Clear
            </Button>
          </div>
        </div>
      )}

      <DataTable
        columns={[
          {
            id: 'select',
            header: '',
            accessorFn: () => null,
            cell: (_val, row) => (
              <input
                type="checkbox"
                checked={selectedIds.has(row.id)}
                onChange={(e) => { e.stopPropagation(); toggleSelected(row.id); }}
                onClick={(e) => e.stopPropagation()}
                className="accent-rose-pink"
              />
            ),
            className: 'w-10',
          },
          ...columns,
        ]}
        data={filtered}
        loading={isLoading}
        onRowClick={(row) => router.push(`/students/${row.id}`)}
        emptyState={
          <EmptyState
            icon={<Icon name="person" size={40} />}
            title="No students found"
            description={search || classFilter.length > 0 ? 'Try adjusting your filters.' : 'Add your first student to get started.'}
            action={!search && classFilter.length === 0 ? <Button onClick={() => setShowCreate(true)}>Add Student</Button> : undefined}
          />
        }
      />

      <StudentFormModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        onSubmit={handleCreate}
        loading={createStudent.isPending}
        classes={classes}
        levelOptions={levelOptions}
      />

      <CSVImportDialog
        open={showImport}
        onClose={() => setShowImport(false)}
      />
    </div>
  );
}
