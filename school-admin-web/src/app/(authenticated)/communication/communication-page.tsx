'use client';

import { useMemo, useState } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { FilterChip } from '@/components/lumi/filter-chip';
import { useToast } from '@/components/lumi/toast';
import { CreateCampaignModal } from './create-campaign-modal';
import {
  useNotificationCampaigns,
  useArchiveCampaign,
  type SerializedCampaign,
} from '@/lib/hooks/use-notifications';

const MESSAGE_TYPE_LABELS: Record<string, string> = {
  reading_reminder: 'Reading reminder',
  announcement: 'Announcement',
  general: 'General',
};

const STATUS_META: Record<
  string,
  { label: string; variant: 'default' | 'success' | 'warning' | 'error' | 'info' }
> = {
  queued: { label: 'Sending…', variant: 'default' },
  processing: { label: 'Sending…', variant: 'default' },
  scheduled: { label: 'Scheduled', variant: 'info' },
  sent: { label: 'Sent', variant: 'success' },
  partial: { label: 'Partly sent', variant: 'warning' },
  failed: { label: 'Failed', variant: 'error' },
};

function formatMessageType(type: string): string {
  return MESSAGE_TYPE_LABELS[type] ?? type;
}

function describeAudience(c: SerializedCampaign): string {
  switch (c.audienceType) {
    case 'school':
      return 'Whole school';
    case 'classes':
      return `${c.targetClassIds.length} class${c.targetClassIds.length === 1 ? '' : 'es'}`;
    case 'students':
      return `${c.targetStudentIds.length} student${c.targetStudentIds.length === 1 ? '' : 's'}`;
    default:
      return c.audienceType;
  }
}

function formatDateTime(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

interface CommunicationPageProps {
  readOnly?: boolean;
}

export function CommunicationPage({ readOnly = false }: CommunicationPageProps) {
  const { toast } = useToast();
  const { data: campaigns, isLoading } = useNotificationCampaigns();
  const archiveCampaign = useArchiveCampaign();
  const [showCreate, setShowCreate] = useState(false);
  const [statusFilter, setStatusFilter] = useState<'active' | 'archived' | 'all'>('active');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const visible = useMemo(() => {
    const list = campaigns ?? [];
    if (statusFilter === 'all') return list;
    return list.filter((c) => (statusFilter === 'archived' ? c.archived : !c.archived));
  }, [campaigns, statusFilter]);

  const changeFilter = (f: 'active' | 'archived' | 'all') => {
    setStatusFilter(f);
    setSelectedIds(new Set());
  };

  const toggleSelect = (id: string) =>
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  const allSelected = visible.length > 0 && visible.every((c) => selectedIds.has(c.id));
  const toggleAll = () => setSelectedIds(allSelected ? new Set() : new Set(visible.map((c) => c.id)));

  const setArchived = async (ids: string[], archived: boolean) => {
    try {
      await Promise.all(ids.map((id) => archiveCampaign.mutateAsync({ campaignId: id, archived })));
      setSelectedIds(new Set());
      toast(
        `${ids.length} message${ids.length === 1 ? '' : 's'} ${archived ? 'archived' : 'unarchived'}`,
        'success'
      );
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Failed to update messages', 'error');
    }
  };
  // Bulk archives in Active/All views, unarchives in the Archived view.
  const bulkArchiveValue = statusFilter !== 'archived';

  const selectColumn: DataTableColumn<SerializedCampaign> = {
    id: 'select',
    header: (
      <input
        type="checkbox"
        checked={allSelected}
        onChange={toggleAll}
        className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
      />
    ),
    accessorFn: (row) => row.id,
    cell: (_, row) => (
      <input
        type="checkbox"
        checked={selectedIds.has(row.id)}
        onChange={() => toggleSelect(row.id)}
        onClick={(e) => e.stopPropagation()}
        className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30"
      />
    ),
    className: 'w-10',
  };

  const actionsColumn: DataTableColumn<SerializedCampaign> = {
    id: 'actions',
    header: '',
    accessorFn: (row) => row.id,
    cell: (_, row) => (
      <div className="text-right" onClick={(e) => e.stopPropagation()}>
        <Button variant="ghost" size="sm" onClick={() => setArchived([row.id], !row.archived)}>
          {row.archived ? 'Unarchive' : 'Archive'}
        </Button>
      </div>
    ),
    className: 'text-right',
  };

  const columns: DataTableColumn<SerializedCampaign>[] = [
    ...(readOnly ? [] : [selectColumn]),
    {
      id: 'title',
      header: 'Message',
      accessorFn: (row) => row.title,
      cell: (val, row) => (
        <div className="max-w-md">
          <p className="font-semibold text-charcoal truncate">{val as string}</p>
          <p className="text-sm text-text-secondary truncate">{row.body}</p>
        </div>
      ),
      sortable: true,
    },
    {
      id: 'audience',
      header: 'Audience',
      accessorFn: (row) => describeAudience(row),
      cell: (val) => <span className="text-sm text-text-secondary">{val as string}</span>,
    },
    {
      id: 'type',
      header: 'Type',
      accessorFn: (row) => formatMessageType(row.messageType),
      cell: (val) => <Badge>{val as string}</Badge>,
    },
    {
      id: 'reach',
      header: 'Reach',
      accessorFn: (row) => row.recipientCounts.parents,
      cell: (val, row) =>
        row.status === 'sent' || row.status === 'partial' ? (
          <span className="text-sm text-text-secondary">
            {val as number} parent{(val as number) === 1 ? '' : 's'}
          </span>
        ) : (
          <span className="text-text-secondary">—</span>
        ),
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => row.status,
      cell: (_, row) => {
        const meta = STATUS_META[row.status] ?? { label: row.status, variant: 'default' as const };
        return (
          <div className="flex flex-col gap-0.5">
            <span>
              <Badge variant={meta.variant}>{meta.label}</Badge>
            </span>
            {row.status === 'scheduled' && row.scheduledFor && (
              <span className="text-xs text-text-secondary">{formatDateTime(row.scheduledFor)}</span>
            )}
            {row.errorSummary && row.status !== 'scheduled' && (
              <span className="text-xs text-text-secondary max-w-[16rem] truncate" title={row.errorSummary}>
                {row.errorSummary}
              </span>
            )}
          </div>
        );
      },
    },
    {
      id: 'created',
      header: 'Created',
      accessorFn: (row) => row.createdAt,
      cell: (val) => <span className="text-sm text-text-secondary">{formatDateTime(val as string)}</span>,
      sortable: true,
    },
    ...(readOnly ? [] : [actionsColumn]),
  ];

  return (
    <div>
      <PageHeader
        title="Communication"
        description="Send notifications to parents in your classes."
        action={
          <Button onClick={() => setShowCreate(true)} disabled={readOnly}>
            New Message
          </Button>
        }
      />

      {readOnly && (
        <div className="mb-4 px-4 py-2.5 rounded-[var(--radius-md)] bg-soft-yellow/40 text-sm text-charcoal">
          Sending is disabled while viewing this school in read-only mode.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2 mb-4">
        {([
          { value: 'active', label: 'Active' },
          { value: 'archived', label: 'Archived' },
          { value: 'all', label: 'All' },
        ] as const).map((opt) => (
          <FilterChip
            key={opt.value}
            label={opt.label}
            selected={statusFilter === opt.value}
            onClick={() => changeFilter(opt.value)}
          />
        ))}
      </div>

      {!readOnly && selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 p-3 bg-rose-pink/5 rounded-[var(--radius-md)] border border-rose-pink/20">
          <span className="text-sm font-semibold text-charcoal">{selectedIds.size} selected</span>
          <Button
            size="sm"
            onClick={() => setArchived([...selectedIds], bulkArchiveValue)}
            loading={archiveCampaign.isPending}
          >
            {bulkArchiveValue ? 'Archive selected' : 'Unarchive selected'}
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setSelectedIds(new Set())}>
            Clear
          </Button>
        </div>
      )}

      <DataTable
        columns={columns}
        data={visible}
        loading={isLoading}
        emptyState={
          (campaigns?.length ?? 0) > 0 ? (
            <EmptyState
              icon={<Icon name="campaign" size={40} />}
              title={statusFilter === 'archived' ? 'No archived messages' : 'No messages match this filter'}
              description={
                statusFilter === 'archived'
                  ? 'Archived messages will appear here.'
                  : 'Try the All filter to see archived messages.'
              }
            />
          ) : (
            <EmptyState
              icon={<Icon name="campaign" size={40} />}
              title="No messages yet"
              description="Send your first notification to parents."
              action={
                <Button onClick={() => setShowCreate(true)} disabled={readOnly}>
                  New Message
                </Button>
              }
            />
          )
        }
      />

      <CreateCampaignModal
        open={showCreate}
        onClose={() => setShowCreate(false)}
        onSent={(scheduled) => {
          setShowCreate(false);
          toast(scheduled ? 'Notification scheduled' : 'Notification sent', 'success');
        }}
      />
    </div>
  );
}
