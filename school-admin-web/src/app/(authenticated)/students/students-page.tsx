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
import { useStudents, useCreateStudent } from '@/lib/hooks/use-students';
import type { SchoolClass, ReadingLevelOption } from '@/lib/types';

type SerializedClass = Omit<SchoolClass, 'createdAt'> & { createdAt: string };

interface StudentsPageProps {
  classes: SerializedClass[];
  levelOptions: ReadingLevelOption[];
}

type QuickFilter = 'all' | 'has-parent' | 'no-parent';

export function StudentsPage({ classes, levelOptions }: StudentsPageProps) {
  const router = useRouter();
  const { toast } = useToast();
  const { data: students, isLoading } = useStudents();
  const createStudent = useCreateStudent();

  const [search, setSearch] = useState('');
  const [classFilter, setClassFilter] = useState<string[]>([]);
  const [quickFilter, setQuickFilter] = useState<QuickFilter>('all');
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

    if (search) {
      const q = search.toLowerCase();
      list = list.filter(
        (s) =>
          `${s.firstName} ${s.lastName}`.toLowerCase().includes(q) ||
          s.studentId?.toLowerCase().includes(q)
      );
    }

    return list;
  }, [students, search, classFilter, quickFilter]);

  const columns: DataTableColumn<(typeof filtered)[0]>[] = [
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
      header: 'Parent',
      accessorFn: (row) => row.parentIds.length > 0,
      cell: (val) =>
        val ? <Badge variant="success">Linked</Badge> : <Badge variant="default">No parent</Badge>,
    },
    {
      id: 'streak',
      header: 'Streak',
      accessorFn: (row) => row.stats?.currentStreak ?? 0,
      cell: (val) => {
        const streak = val as number;
        return streak > 0 ? (
          <span className="text-sm font-semibold text-charcoal">{streak} days</span>
        ) : (
          <span className="text-sm text-text-secondary">-</span>
        );
      },
      sortable: true,
    },
  ];

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
              label={c.name}
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
          {(['all', 'has-parent', 'no-parent'] as const).map((filter) => (
            <FilterChip
              key={filter}
              label={filter === 'all' ? 'All' : filter === 'has-parent' ? 'Has Parent' : 'No Parent'}
              selected={quickFilter === filter}
              onClick={() => setQuickFilter(filter)}
            />
          ))}
        </div>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by name or student ID..." />
      </div>

      <DataTable
        columns={columns}
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
