'use client';

import { useState, useMemo } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Avatar } from '@/components/lumi/avatar';
import { SearchInput } from '@/components/lumi/search-input';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { InfoTooltip } from '@/components/lumi/tooltip';
import { useUsers } from '@/lib/hooks/use-users';
import { useStaffOnboardingEmails, type StaffOnboardingEmailRecord } from '@/lib/hooks/use-staff-onboarding-emails';
import { SendStaffOnboardingModal } from './send-staff-onboarding-modal';
import { StaffEmailPreviewModal } from './staff-email-preview-modal';

type StaffRow = NonNullable<ReturnType<typeof useUsers>['data']>[number];
type OnboardStatus = 'registered' | 'pending';

/** Signed in once → registered; never signed in → still needs onboarding. */
function getStatus(u: StaffRow): OnboardStatus {
  return u.lastLoginAt ? 'registered' : 'pending';
}

const statusLabel: Record<OnboardStatus, string> = { registered: 'Signed in', pending: 'Pending' };
const statusVariant: Record<OnboardStatus, 'success' | 'warning'> = { registered: 'success', pending: 'warning' };
const emailStatusVariants: Record<string, 'success' | 'warning' | 'error' | 'default'> = {
  sent: 'success',
  partial: 'warning',
  failed: 'error',
  processing: 'default',
  queued: 'default',
};

export function StaffOnboardingTab() {
  const { data: allUsers, isLoading } = useUsers();
  const { data: emailHistory, isLoading: emailsLoading } = useStaffOnboardingEmails();

  const staff = useMemo(
    () => (allUsers ?? []).filter((u) => (u.role === 'teacher' || u.role === 'schoolAdmin') && u.isActive),
    [allUsers]
  );

  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<OnboardStatus | 'all'>('all');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showSend, setShowSend] = useState(false);
  const [showPreview, setShowPreview] = useState(false);

  const filtered = useMemo(
    () =>
      staff
        .filter((u) => statusFilter === 'all' || getStatus(u) === statusFilter)
        .filter((u) => {
          if (!search.trim()) return true;
          const q = search.toLowerCase().trim();
          return u.fullName.toLowerCase().includes(q) || u.email.toLowerCase().includes(q);
        }),
    [staff, statusFilter, search]
  );

  const registered = staff.filter((u) => getStatus(u) === 'registered').length;
  const total = staff.length;
  const pct = total ? Math.round((registered / total) * 100) : 0;

  const toggleSelect = (id: string) =>
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const selectAllPending = () =>
    setSelectedIds(new Set(filtered.filter((u) => getStatus(u) === 'pending').map((u) => u.id)));

  const columns: DataTableColumn<StaffRow>[] = [
    {
      id: 'select',
      header: '',
      accessorFn: (r) => r.id,
      cell: (_, r) => (
        <input
          type="checkbox"
          checked={selectedIds.has(r.id)}
          onChange={(e) => {
            e.stopPropagation();
            toggleSelect(r.id);
          }}
          className="w-4 h-4 rounded border-rule text-section focus:ring-section/30 cursor-pointer"
        />
      ),
      className: 'w-10',
    },
    {
      id: 'name',
      header: 'Name',
      accessorFn: (r) => r.fullName,
      cell: (v, r) => (
        <span className="flex items-center gap-2">
          <Avatar name={r.fullName} characterId={r.characterId} size="sm" />
          <span className="font-semibold text-ink">{v as string}</span>
        </span>
      ),
      sortable: true,
    },
    {
      id: 'email',
      header: 'Email',
      accessorFn: (r) => r.email,
      cell: (v) => <span className="text-sm text-ink">{v as string}</span>,
      sortable: true,
    },
    {
      id: 'role',
      header: 'Role',
      accessorFn: (r) => r.role,
      cell: (v) => <Badge variant={v === 'schoolAdmin' ? 'info' : 'default'}>{v === 'schoolAdmin' ? 'Admin' : 'Teacher'}</Badge>,
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (r) => getStatus(r),
      cell: (v) => <Badge variant={statusVariant[v as OnboardStatus]}>{statusLabel[v as OnboardStatus]}</Badge>,
    },
  ];

  return (
    <div>
      {/* Status guide */}
      <div className="flex items-center gap-1.5 mb-4">
        <span className="text-sm font-semibold text-muted">Onboarding Status</span>
        <InfoTooltip>
          <strong>Signed in</strong> = the staff member has logged in.{' '}
          <strong>Pending</strong> = hasn&apos;t signed in yet — an onboarding email gives them what they need.
        </InfoTooltip>
      </div>

      {/* Stats */}
      <div className="bg-paper shadow-card rounded-[var(--radius-lg)] p-4 mb-6 space-y-3">
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold text-ink whitespace-nowrap">{registered} / {total} signed in</span>
          <div className="flex-1 h-2 rounded-full bg-cream overflow-hidden">
            <div className="h-full bg-lumi-green rounded-full transition-all duration-500" style={{ width: `${pct}%` }} />
          </div>
          <span className="text-sm font-medium text-muted w-10 text-right">{pct}%</span>
        </div>
        <div className="flex flex-wrap gap-2">
          {(['registered', 'pending'] as OnboardStatus[]).map((s) => {
            const count = staff.filter((u) => getStatus(u) === s).length;
            const isActive = statusFilter === s;
            const colors: Record<OnboardStatus, string> = {
              registered: 'border-lumi-green/60 text-lumi-green-dark bg-lumi-green/10',
              pending: 'border-lumi-yellow/60 text-ink bg-lumi-yellow/20',
            };
            return (
              <button
                key={s}
                onClick={() => setStatusFilter(isActive ? 'all' : s)}
                className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-all ${colors[s]} ${
                  isActive ? 'ring-2 ring-offset-1 ring-current opacity-100' : 'opacity-70 hover:opacity-100'
                }`}
              >
                {statusLabel[s]}: {count}
              </button>
            );
          })}
        </div>
      </div>

      {/* Search + Preview */}
      <div className="flex items-center gap-3 mb-4">
        <div className="flex-1">
          <SearchInput value={search} onChange={setSearch} placeholder="Search by name or email..." />
        </div>
        <Button variant="outline" size="md" onClick={() => setShowPreview(true)}>
          Preview Email
        </Button>
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 px-4 py-3 bg-section/5 border border-section/20 rounded-[var(--radius-md)]">
          <span className="text-sm font-semibold text-ink">{selectedIds.size} selected</span>
          <Button variant="outline" size="sm" onClick={selectAllPending}>
            Select All Pending
          </Button>
          <Button size="sm" onClick={() => setShowSend(true)}>
            Send Onboarding Emails
          </Button>
          <Button variant="ghost" size="sm" onClick={() => setSelectedIds(new Set())}>
            Clear Selection
          </Button>
        </div>
      )}

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        emptyState={
          <EmptyState
            icon={<Icon name="group" size={40} />}
            title="No staff found"
            description="Adjust your search to find staff members."
          />
        }
      />

      {filtered.length > 0 && selectedIds.size === 0 && (
        <div className="flex items-center gap-4 mt-3">
          <button
            onClick={() => setSelectedIds(new Set(filtered.map((u) => u.id)))}
            className="text-sm text-section hover:underline font-semibold"
          >
            Select all {filtered.length} visible
          </button>
          <button onClick={selectAllPending} className="text-sm text-section hover:underline font-semibold">
            Select all pending
          </button>
        </div>
      )}

      {/* Email history */}
      <div className="mt-8">
        <h3 className="text-lg font-bold text-ink mb-4">Email History</h3>
        {emailsLoading ? (
          <p className="text-sm text-muted">Loading…</p>
        ) : !emailHistory || emailHistory.length === 0 ? (
          <p className="text-sm text-muted">No emails sent yet</p>
        ) : (
          <div className="space-y-3">
            {emailHistory.map((record: StaffOnboardingEmailRecord) => (
              <div
                key={record.id}
                className="bg-paper shadow-card rounded-[var(--radius-lg)] p-4 flex items-center justify-between"
              >
                <div className="flex items-center gap-4">
                  <div>
                    <p className="text-sm font-semibold text-ink">
                      {new Date(record.createdAt).toLocaleDateString(undefined, {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </p>
                    {record.emailSubject && <p className="text-xs text-muted mt-0.5">{record.emailSubject}</p>}
                  </div>
                  <Badge variant={emailStatusVariants[record.status] ?? 'default'}>
                    {record.status.charAt(0).toUpperCase() + record.status.slice(1)}
                  </Badge>
                </div>
                <div className="text-sm text-muted">
                  {record.deliveryCounts ? (
                    <span>
                      {record.deliveryCounts.sent} sent
                      {record.deliveryCounts.skipped > 0 && `, ${record.deliveryCounts.skipped} skipped`}
                      {record.deliveryCounts.failed > 0 && `, ${record.deliveryCounts.failed} failed`}
                    </span>
                  ) : record.recipientCount != null ? (
                    <span>{record.recipientCount} recipients</span>
                  ) : null}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Modals */}
      <SendStaffOnboardingModal
        open={showSend}
        onClose={() => setShowSend(false)}
        selectedUserIds={Array.from(selectedIds)}
        staff={staff.map((u) => ({
          id: u.id,
          fullName: u.fullName,
          email: u.email,
          role: u.role as 'teacher' | 'schoolAdmin',
          lastLoginAt: u.lastLoginAt,
        }))}
        onSuccess={() => {
          setSelectedIds(new Set());
          setShowSend(false);
        }}
      />
      <StaffEmailPreviewModal open={showPreview} onClose={() => setShowPreview(false)} />
    </div>
  );
}
