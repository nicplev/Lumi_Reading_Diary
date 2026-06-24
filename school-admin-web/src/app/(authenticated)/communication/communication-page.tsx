'use client';

import { useState } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Badge } from '@/components/lumi/badge';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { useToast } from '@/components/lumi/toast';
import { CreateCampaignModal } from './create-campaign-modal';
import {
  useNotificationCampaigns,
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
  const [showCreate, setShowCreate] = useState(false);

  const columns: DataTableColumn<SerializedCampaign>[] = [
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

      <DataTable
        columns={columns}
        data={campaigns ?? []}
        loading={isLoading}
        emptyState={
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
