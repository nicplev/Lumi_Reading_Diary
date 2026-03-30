'use client';

import { useState } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { useToast } from '@/components/lumi/toast';
import { useAllocations, useDeactivateAllocation } from '@/lib/hooks/use-allocations';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { AllocationFormModal } from './allocation-form-modal';
import { AllocationDetail } from './allocation-detail';
import type { ReadingLevelOption } from '@/lib/types';

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
  const { data: allocations, isLoading } = useAllocations({ classId });
  const deactivate = useDeactivateAllocation();

  const [showCreate, setShowCreate] = useState(false);
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [deactivateConfirm, setDeactivateConfirm] = useState<string | null>(null);

  const handleDeactivate = async () => {
    if (!deactivateConfirm) return;
    try {
      await deactivate.mutateAsync(deactivateConfirm);
      toast('Allocation deactivated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to deactivate', 'error');
    }
    setDeactivateConfirm(null);
  };

  const columns: DataTableColumn<SerializedAllocation>[] = [
    {
      id: 'type',
      header: 'Type',
      accessorFn: (row) => row.type,
      cell: (value) => {
        const t = typeLabels[value as string] ?? { label: value as string, variant: 'default' as const };
        return <Badge variant={t.variant}>{t.label}</Badge>;
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
          {row.isActive && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setDeactivateConfirm(row.id)}
              className="text-error hover:text-error"
            >
              Deactivate
            </Button>
          )}
        </div>
      ),
      className: 'text-right',
    },
  ];

  return (
    <div className="mt-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-text-secondary uppercase tracking-wider">Allocations</h3>
        <Button size="sm" onClick={() => setShowCreate(true)}>
          Create Allocation
        </Button>
      </div>

      <DataTable
        columns={columns}
        data={allocations ?? []}
        loading={isLoading}
        onRowClick={(row) => setExpandedId(expandedId === row.id ? null : row.id)}
        emptyState={
          <EmptyState
            icon={<Icon name="inventory_2" size={40} />}
            title="No allocations"
            description="Create an allocation to assign books to this class."
            action={<Button onClick={() => setShowCreate(true)}>Create Allocation</Button>}
          />
        }
      />

      {expandedId && allocations && (
        <div className="mt-4">
          <AllocationDetail
            allocation={allocations.find((a) => a.id === expandedId)!}
            onClose={() => setExpandedId(null)}
          />
        </div>
      )}

      <AllocationFormModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        classId={classId}
        levelOptions={levelOptions}
      />

      <ConfirmDialog
        open={!!deactivateConfirm}
        onClose={() => setDeactivateConfirm(null)}
        onConfirm={handleDeactivate}
        title="Deactivate Allocation"
        description="This allocation will be marked as inactive. Students will no longer see these assignments."
        confirmLabel="Deactivate"
        variant="danger"
        loading={deactivate.isPending}
      />
    </div>
  );
}
