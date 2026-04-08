'use client';

import { useState, useMemo } from 'react';
import { Badge } from '@/components/lumi/badge';
import { SearchInput } from '@/components/lumi/search-input';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { useParents } from '@/lib/hooks/use-parents';
import { useClasses } from '@/lib/hooks/use-classes';

type SerializedParent = NonNullable<ReturnType<typeof useParents>['data']>[number];

export function ParentConnectionsTab() {
  const { data: parents, isLoading } = useParents();
  const { data: classes } = useClasses();
  const [search, setSearch] = useState('');

  const classMap = useMemo(() => {
    const map = new Map<string, string>();
    if (classes) {
      for (const c of classes) map.set(c.id, c.name);
    }
    return map;
  }, [classes]);

  const filtered = useMemo(() => {
    if (!parents) return [];
    if (!search.trim()) return parents;

    const q = search.toLowerCase().trim();
    return parents.filter((p) =>
      p.fullName.toLowerCase().includes(q) ||
      p.email.toLowerCase().includes(q) ||
      p.linkedStudents.some((s) =>
        `${s.firstName} ${s.lastName}`.toLowerCase().includes(q)
      )
    );
  }, [parents, search]);

  const columns: DataTableColumn<SerializedParent>[] = [
    {
      id: 'name',
      header: 'Parent Name',
      accessorFn: (row) => row.fullName,
      sortable: true,
    },
    {
      id: 'email',
      header: 'Email',
      accessorFn: (row) => row.email,
      sortable: true,
    },
    {
      id: 'students',
      header: 'Linked Students',
      accessorFn: (row) => row.linkedStudents.length,
      cell: (_, row) =>
        row.linkedStudents.length === 0 ? (
          <span className="text-text-secondary text-sm">No students linked</span>
        ) : (
          <div className="flex flex-wrap gap-1.5">
            {row.linkedStudents.map((s) => (
              <Badge key={s.id} variant="info">
                {s.firstName} {s.lastName}
                {classMap.get(s.classId) ? ` (${classMap.get(s.classId)})` : ''}
              </Badge>
            ))}
          </div>
        ),
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => row.isActive,
      cell: (value) => (
        <Badge variant={value ? 'success' : 'default'}>
          {value ? 'Active' : 'Inactive'}
        </Badge>
      ),
    },
    {
      id: 'lastLogin',
      header: 'Last Login',
      accessorFn: (row) => row.lastLoginAt,
      cell: (value) =>
        value ? (
          <span className="text-sm">{new Date(value as string).toLocaleDateString()}</span>
        ) : (
          <span className="text-sm text-text-secondary">Never</span>
        ),
      sortable: true,
    },
    {
      id: 'created',
      header: 'Joined',
      accessorFn: (row) => row.createdAt,
      cell: (value) => new Date(value as string).toLocaleDateString(),
      sortable: true,
    },
  ];

  return (
    <div>
      <div className="mb-4">
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Search by parent name, email, or student name..."
        />
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyState={
          <EmptyState
            icon={<Icon name="family_restroom" size={40} />}
            title="No parent accounts"
            description="Parents can register through the mobile app using link codes. Generate codes in the Link Codes tab."
          />
        }
      />
    </div>
  );
}
