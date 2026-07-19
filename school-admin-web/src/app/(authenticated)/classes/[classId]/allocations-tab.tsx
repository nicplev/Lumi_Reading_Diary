'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { FilterChip } from '@/components/lumi/filter-chip';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { useToast } from '@/components/lumi/toast';
import { useAllocations, useDeleteAllocation } from '@/lib/hooks/use-allocations';
import { useStudents } from '@/lib/hooks/use-students';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { AllocationFormModal } from './allocation-form-modal';
import { AllocationDetail } from './allocation-detail';
import type { ReadingLevelOption } from '@/lib/types';
import { useAuth } from '@/lib/auth/auth-context';

interface AllocationsTabProps {
  classId: string;
  levelOptions: ReadingLevelOption[];
}

type SerializedAllocation = NonNullable<ReturnType<typeof useAllocations>['data']>[number];

const typeLabels: Record<string, { label: string; variant: 'info' | 'success' | 'warning' }> = {
  byTitle: { label: 'By Title', variant: 'info' },
  byLevel: { label: 'By Level', variant: 'success' },
  freeChoice: { label: 'Free Choice', variant: 'warning' },
};

const cadenceLabels: Record<string, string> = {
  daily: 'Daily',
  weekly: 'Weekly',
  fortnightly: 'Fortnightly',
  custom: 'Custom',
};

export function AllocationsTab({ classId, levelOptions }: AllocationsTabProps) {
  const { toast } = useToast();
  const { user } = useAuth();
  const isDemo = user?.demoAllocationMutations === true;
  const { data: allocations, isLoading } = useAllocations({ classId });
  const { data: students } = useStudents({ classId });
  const deleteAllocation = useDeleteAllocation();

  const [showCreate, setShowCreate] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<'current' | 'expired' | 'all'>('current');
  const detailRef = useRef<HTMLDivElement>(null);

  const expandedAllocation = expandedId
    ? allocations?.find((a) => a.id === expandedId)
    : undefined;

  // Hide expired allocations by default (endDate < now); newest first. Teachers
  // can switch to Expired/All to find old ones. The Date Range header re-sorts.
  const visibleAllocations = useMemo(() => {
    const nowIso = new Date().toISOString();
    const list = (allocations ?? []).filter((a) => {
      if (statusFilter === 'all') return true;
      const expired = a.endDate < nowIso;
      return statusFilter === 'expired' ? expired : !expired;
    });
    return [...list].sort((a, b) => b.startDate.localeCompare(a.startDate));
  }, [allocations, statusFilter]);

  // The detail panel renders at the top of the tab; bring it into view on open.
  useEffect(() => {
    if (expandedAllocation) {
      detailRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }
  }, [expandedAllocation]);

  const handleDelete = async () => {
    if (!deleteConfirm) return;
    try {
      await deleteAllocation.mutateAsync(deleteConfirm);
      if (expandedId === deleteConfirm) setExpandedId(null);
      toast('Allocation deleted', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to delete', 'error');
    }
    setDeleteConfirm(null);
  };

  const columns: DataTableColumn<SerializedAllocation>[] = [
    {
      id: 'type',
      header: 'Type',
      accessorFn: (row) => row.type,
      cell: (value, row) => {
        const t = typeLabels[value as string] ?? { label: value as string, variant: 'default' as const };
        return (
          <div className="flex flex-wrap gap-1">
            <Badge variant={t.variant}>{t.label}</Badge>
            {row.demoEphemeral && <Badge variant="warning">Temporary demo</Badge>}
          </div>
        );
      },
    },
    {
      id: 'cadence',
      header: 'Cadence',
      accessorFn: (row) => row.cadence,
      cell: (value) => cadenceLabels[value as string] ?? (value as string),
    },
    {
      id: 'dates',
      header: 'Date Range',
      accessorFn: (row) => row.startDate,
      cell: (_, row) => {
        const start = new Date(row.startDate).toLocaleDateString();
        const end = new Date(row.endDate).toLocaleDateString();
        return <span className="text-xs">{start} - {end}</span>;
      },
      sortable: true,
    },
    {
      id: 'assignedTo',
      header: 'Assigned To',
      accessorFn: (row) => row.studentIds.length,
      cell: (_, row) =>
        row.studentIds.length === 0 ? (
          <span className="text-sm">Whole class</span>
        ) : (
          <span className="text-sm">
            {row.studentIds.length} student{row.studentIds.length === 1 ? '' : 's'}
          </span>
        ),
    },
    {
      id: 'books',
      header: 'Books',
      accessorFn: (row) => row.assignmentItems?.filter((i) => !i.isDeleted).length ?? 0,
      cell: (value) => <span className="font-semibold">{value as number}</span>,
    },
    {
      id: 'target',
      header: 'Target Min',
      accessorFn: (row) => row.targetMinutes,
      cell: (value) => `${value}min`,
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => row.isActive,
      cell: (value, row) => {
        if (!value) return <Badge variant="default">Inactive</Badge>;
        const now = new Date().toISOString();
        if (row.endDate < now) return <Badge variant="warning">Expired</Badge>;
        return <Badge variant="success">Active</Badge>;
      },
    },
    {
      id: 'actions',
      header: '',
      accessorFn: (row) => row.id,
      cell: (_, row) => (
        <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setExpandedId(expandedId === row.id ? null : row.id)}
          >
            {expandedId === row.id ? 'Close' : 'Details'}
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setDeleteConfirm(row.id)}
            className="text-error hover:text-error"
            disabled={isDemo && !row.demoEphemeral}
            title={isDemo && !row.demoEphemeral ? 'Seeded demo allocations cannot be deleted' : undefined}
          >
            Delete
          </Button>
        </div>
      ),
      className: 'text-right',
    },
  ];

  return (
    <div className="mt-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-muted uppercase tracking-wider">Allocations</h3>
        <Button size="sm" onClick={() => setShowCreate(true)}>
          Create Allocation
        </Button>
      </div>

      {isDemo && (
        <div className="mb-4 rounded-[var(--radius-md)] border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-ink">
          New allocations are temporary and reset when the demo is reprovisioned. Seeded allocations remain read-only.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 mb-4">
        {([
          { value: 'current', label: 'Current' },
          { value: 'expired', label: 'Expired' },
          { value: 'all', label: 'All' },
        ] as const).map((opt) => (
          <FilterChip
            key={opt.value}
            label={opt.label}
            selected={statusFilter === opt.value}
            onClick={() => setStatusFilter(opt.value)}
          />
        ))}
      </div>

      {expandedAllocation && (
        <div ref={detailRef} className="mb-4 scroll-mt-4">
          <AllocationDetail
            allocation={expandedAllocation}
            students={students}
            onClose={() => setExpandedId(null)}
          />
        </div>
      )}

      <DataTable
        columns={columns}
        data={visibleAllocations}
        loading={isLoading}
        onRowClick={(row) => setExpandedId(expandedId === row.id ? null : row.id)}
        emptyState={
          (allocations?.length ?? 0) > 0 ? (
            <EmptyState
              icon={<Icon name="inventory_2" size={40} />}
              title="No allocations match this filter"
              description="Switch to Expired or All to see older allocations."
            />
          ) : (
            <EmptyState
              icon={<Icon name="inventory_2" size={40} />}
              title="No allocations"
              description="Create an allocation to assign books to this class."
              action={<Button onClick={() => setShowCreate(true)}>Create Allocation</Button>}
            />
          )
        }
      />

      <AllocationFormModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        classId={classId}
        levelOptions={levelOptions}
      />

      <ConfirmDialog
        open={!!deleteConfirm}
        onClose={() => setDeleteConfirm(null)}
        onConfirm={handleDelete}
        title="Delete Allocation"
        description="This permanently deletes the allocation — students will no longer see these assignments. This can't be undone."
        confirmLabel="Delete"
        variant="danger"
        loading={deleteAllocation.isPending}
      />
    </div>
  );
}
