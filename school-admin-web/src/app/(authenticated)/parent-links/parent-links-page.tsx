'use client';

import { useState, useMemo } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Card } from '@/components/lumi/card';
import { SearchInput } from '@/components/lumi/search-input';
import { FilterChip } from '@/components/lumi/filter-chip';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { useLinkCodes, useCreateLinkCode, useRevokeLinkCode, useBulkCreateLinkCodes } from '@/lib/hooks/use-link-codes';
import { useStudents } from '@/lib/hooks/use-students';
import { useClasses } from '@/lib/hooks/use-classes';
import { GenerateCodeModal } from './generate-code-modal';

type StatusFilter = 'all' | 'active' | 'used' | 'revoked' | 'expired';
type SerializedCode = NonNullable<ReturnType<typeof useLinkCodes>['data']>[number];

const statusVariants: Record<string, 'success' | 'info' | 'warning' | 'error' | 'default'> = {
  active: 'success',
  used: 'info',
  revoked: 'error',
  expired: 'warning',
};

export function ParentLinksPage() {
  const { toast } = useToast();
  const { data: codes, isLoading } = useLinkCodes();
  const revoke = useRevokeLinkCode();

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const [showGenerate, setShowGenerate] = useState(false);
  const [revokeConfirm, setRevokeConfirm] = useState<string | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const filtered = useMemo(() => {
    if (!codes) return [];
    let result = [...codes];

    if (statusFilter !== 'all') {
      result = result.filter((c) => c.status === statusFilter);
    }

    if (search.trim()) {
      const q = search.toLowerCase().trim();
      result = result.filter(
        (c) =>
          c.code.toLowerCase().includes(q) ||
          c.studentName.toLowerCase().includes(q)
      );
    }

    return result;
  }, [codes, statusFilter, search]);

  const statusCounts = useMemo(() => {
    if (!codes) return { all: 0, active: 0, used: 0, revoked: 0, expired: 0 };
    return {
      all: codes.length,
      active: codes.filter((c) => c.status === 'active').length,
      used: codes.filter((c) => c.status === 'used').length,
      revoked: codes.filter((c) => c.status === 'revoked').length,
      expired: codes.filter((c) => c.status === 'expired').length,
    };
  }, [codes]);

  const handleRevoke = async () => {
    if (!revokeConfirm) return;
    try {
      await revoke.mutateAsync(revokeConfirm);
      toast('Link code revoked', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to revoke', 'error');
    }
    setRevokeConfirm(null);
  };

  const handleCopy = (code: string, id: string) => {
    navigator.clipboard.writeText(code);
    setCopiedId(id);
    setTimeout(() => setCopiedId(null), 2000);
    toast('Code copied to clipboard', 'success');
  };

  const columns: DataTableColumn<SerializedCode>[] = [
    {
      id: 'code',
      header: 'Code',
      accessorFn: (row) => row.code,
      cell: (value, row) => (
        <div className="flex items-center gap-2">
          <code className="bg-background px-2 py-1 rounded text-sm font-mono font-bold text-charcoal">
            {value as string}
          </code>
          <button
            onClick={(e) => { e.stopPropagation(); handleCopy(value as string, row.id); }}
            className="text-text-secondary hover:text-charcoal transition-colors"
            title="Copy code"
          >
            {copiedId === row.id ? (
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M3 7l3 3 5-5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
            ) : (
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><rect x="4" y="4" width="8" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.2" /><path d="M10 4V3a1.5 1.5 0 00-1.5-1.5H3A1.5 1.5 0 001.5 3v5.5A1.5 1.5 0 003 10h1" stroke="currentColor" strokeWidth="1.2" /></svg>
            )}
          </button>
        </div>
      ),
      sortable: true,
    },
    {
      id: 'student',
      header: 'Student',
      accessorFn: (row) => row.studentName,
      sortable: true,
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => row.status,
      cell: (value) => (
        <Badge variant={statusVariants[value as string] ?? 'default'}>
          {(value as string).charAt(0).toUpperCase() + (value as string).slice(1)}
        </Badge>
      ),
    },
    {
      id: 'created',
      header: 'Created',
      accessorFn: (row) => row.createdAt,
      cell: (value) => new Date(value as string).toLocaleDateString(),
      sortable: true,
    },
    {
      id: 'expires',
      header: 'Expires',
      accessorFn: (row) => row.expiresAt,
      cell: (value) => new Date(value as string).toLocaleDateString(),
    },
    {
      id: 'actions',
      header: '',
      accessorFn: (row) => row.id,
      cell: (_, row) =>
        row.status === 'active' ? (
          <Button
            variant="ghost"
            size="sm"
            onClick={(e) => { e.stopPropagation(); setRevokeConfirm(row.id); }}
            className="text-error hover:text-error"
          >
            Revoke
          </Button>
        ) : null,
      className: 'text-right',
    },
  ];

  return (
    <div>
      <PageHeader
        title="Parent Links"
        description="Manage parent linking codes"
        action={
          <Button onClick={() => setShowGenerate(true)}>
            Generate Code
          </Button>
        }
      />

      <div className="flex flex-wrap items-center gap-3 mb-4">
        {([
          { value: 'all', label: 'All', count: statusCounts.all },
          { value: 'active', label: 'Active', count: statusCounts.active },
          { value: 'used', label: 'Used', count: statusCounts.used },
          { value: 'revoked', label: 'Revoked', count: statusCounts.revoked },
          { value: 'expired', label: 'Expired', count: statusCounts.expired },
        ] as const).map((opt) => (
          <FilterChip
            key={opt.value}
            label={opt.label}
            count={opt.count}
            selected={statusFilter === opt.value}
            onClick={() => setStatusFilter(opt.value)}
          />
        ))}
      </div>

      <div className="mb-4">
        <SearchInput value={search} onChange={setSearch} placeholder="Search by code or student name..." />
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyState={
          <EmptyState
            icon={<Icon name="link" size={40} />}
            title="No link codes"
            description="Generate codes for parents to link to their children."
            action={<Button onClick={() => setShowGenerate(true)}>Generate Code</Button>}
          />
        }
      />

      <GenerateCodeModal
        open={showGenerate}
        onClose={() => setShowGenerate(false)}
      />

      <ConfirmDialog
        open={!!revokeConfirm}
        onClose={() => setRevokeConfirm(null)}
        onConfirm={handleRevoke}
        title="Revoke Link Code"
        description="This code will no longer be usable. The parent will need a new code to link."
        confirmLabel="Revoke"
        variant="danger"
        loading={revoke.isPending}
      />
    </div>
  );
}
