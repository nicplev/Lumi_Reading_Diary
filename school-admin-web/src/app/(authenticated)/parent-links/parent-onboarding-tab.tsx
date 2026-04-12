'use client';

import { useState, useMemo } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { FilterChip } from '@/components/lumi/filter-chip';
import { SearchInput } from '@/components/lumi/search-input';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { InfoTooltip } from '@/components/lumi/tooltip';
import { useToast } from '@/components/lumi/toast';
import { useStudents } from '@/lib/hooks/use-students';
import { useClasses } from '@/lib/hooks/use-classes';
import { useOnboardingEmails, type OnboardingEmailRecord } from '@/lib/hooks/use-onboarding-emails';
import { SendOnboardingEmailModal } from './send-onboarding-email-modal';
import { EmailPreviewModal } from './email-preview-modal';
import type { EnrollmentStatus } from '@/lib/types';

type OnboardingStatus = 'linked' | 'ready' | 'pending' | 'no_subscription';

type StudentRow = {
  id: string;
  firstName: string;
  lastName: string;
  classId: string;
  parentEmail?: string;
  enrollmentStatus?: EnrollmentStatus;
  parentIds: string[];
};

function getOnboardingStatus(student: StudentRow): OnboardingStatus {
  if (student.parentIds.length > 0) return 'linked';
  if (!student.enrollmentStatus || student.enrollmentStatus === 'not_enrolled') return 'no_subscription';
  if (student.enrollmentStatus === 'pending') return 'pending';
  return 'ready'; // book_pack or direct_purchase, not yet linked
}

const onboardingStatusLabel: Record<OnboardingStatus, string> = {
  linked: 'Linked',
  ready: 'Ready',
  pending: 'Pending',
  no_subscription: 'No Subscription',
};

const onboardingStatusVariant: Record<OnboardingStatus, 'success' | 'warning' | 'info' | 'default'> = {
  linked: 'success',
  ready: 'warning',
  pending: 'info',
  no_subscription: 'default',
};

const emailStatusVariants: Record<string, 'success' | 'warning' | 'error' | 'default'> = {
  sent: 'success',
  partial: 'warning',
  failed: 'error',
  processing: 'default',
  queued: 'default',
};

export function ParentOnboardingTab() {
  const { toast } = useToast();
  const { data: students, isLoading: studentsLoading } = useStudents();
  const { data: classes } = useClasses();
  const { data: emailHistory, isLoading: emailsLoading } = useOnboardingEmails();

  const classMap = useMemo(() => {
    if (!classes) return new Map<string, string>();
    return new Map(classes.map((c) => [c.id, c.name]));
  }, [classes]);

  const [search, setSearch] = useState('');
  const [classFilter, setClassFilter] = useState<string>('all');
  const [statusFilter, setStatusFilter] = useState<OnboardingStatus | 'all'>('all');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showSendModal, setShowSendModal] = useState(false);
  const [showPreviewModal, setShowPreviewModal] = useState(false);

  const activeStudents = useMemo(() => {
    if (!students) return [];
    return students.filter((s) => s.isActive) as StudentRow[];
  }, [students]);

  const uniqueClassIds = useMemo(() => {
    const ids = new Set(activeStudents.map((s) => s.classId));
    return Array.from(ids).filter((id) => classMap.has(id)).sort();
  }, [activeStudents, classMap]);

  // Stats
  const stats = useMemo(() => {
    const linked = activeStudents.filter((s) => s.parentIds.length > 0).length;
    const emailsSent = emailHistory?.reduce(
      (sum, record) => sum + (record.deliveryCounts?.sent ?? 0),
      0
    ) ?? 0;
    return { linked, emailsSent };
  }, [activeStudents, emailHistory]);

  // Filtering
  const filtered = useMemo(() => {
    return activeStudents
      .filter((s) => classFilter === 'all' || s.classId === classFilter)
      .filter((s) => statusFilter === 'all' || getOnboardingStatus(s) === statusFilter)
      .filter((s) => {
        if (!search.trim()) return true;
        const q = search.toLowerCase().trim();
        return (
          `${s.firstName} ${s.lastName}`.toLowerCase().includes(q) ||
          (s.parentEmail && s.parentEmail.toLowerCase().includes(q)) ||
          s.classId.toLowerCase().includes(q)
        );
      });
  }, [activeStudents, classFilter, statusFilter, search]);

  // Selection helpers
  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const toggleSelectAll = () => {
    if (selectedIds.size === filtered.length && filtered.length > 0) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(filtered.map((s) => s.id)));
    }
  };

  const selectAllEligible = () => {
    const eligible = filtered.filter(
      (s) =>
        !!s.parentEmail &&
        (s.enrollmentStatus === 'book_pack' || s.enrollmentStatus === 'direct_purchase') &&
        s.parentIds.length === 0
    );
    setSelectedIds(new Set(eligible.map((s) => s.id)));
    toast(`${eligible.length} eligible student${eligible.length !== 1 ? 's' : ''} selected`, 'info');
  };

  const handleSendSuccess = () => {
    setSelectedIds(new Set());
    setShowSendModal(false);
  };

  const columns: DataTableColumn<StudentRow>[] = [
    {
      id: 'select',
      header: '',
      accessorFn: (row) => row.id,
      cell: (_, row) => (
        <input
          type="checkbox"
          checked={selectedIds.has(row.id)}
          onChange={(e) => {
            e.stopPropagation();
            toggleSelect(row.id);
          }}
          className="w-4 h-4 rounded border-divider text-rose-pink focus:ring-rose-pink/30 cursor-pointer"
        />
      ),
      className: 'w-10',
    },
    {
      id: 'name',
      header: 'Name',
      accessorFn: (row) => `${row.firstName} ${row.lastName}`,
      sortable: true,
    },
    {
      id: 'class',
      header: 'Class',
      accessorFn: (row) => classMap.get(row.classId) || row.classId,
      sortable: true,
    },
    {
      id: 'parentEmail',
      header: 'Parent Email',
      accessorFn: (row) => row.parentEmail ?? '',
      cell: (value) =>
        value ? (
          <span className="text-sm text-charcoal">{value as string}</span>
        ) : (
          <span className="text-sm text-text-secondary/50 italic">No email</span>
        ),
      sortable: true,
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => getOnboardingStatus(row),
      cell: (value) => (
        <Badge variant={onboardingStatusVariant[value as OnboardingStatus]}>
          {onboardingStatusLabel[value as OnboardingStatus]}
        </Badge>
      ),
    },
  ];

  if (studentsLoading) {
    return (
      <div className="space-y-4">
        <div className="bg-surface shadow-card rounded-[var(--radius-lg)] p-4 animate-pulse">
          <div className="h-4 w-48 bg-background rounded mb-3" />
          <div className="h-2 w-full bg-background rounded mb-4" />
          <div className="flex gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="h-8 w-28 bg-background rounded-full" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  const total = activeStudents.length;
  const linkedPct = total ? Math.round((stats.linked / total) * 100) : 0;

  return (
    <div>
      {/* Status guide (inline tooltip) */}
      <div className="flex items-center gap-1.5 mb-4">
        <span className="text-sm font-semibold text-text-secondary">Onboarding Status Guide</span>
        <InfoTooltip>
          <strong>Linked</strong> = parent account connected.{' '}
          <strong>Ready</strong> = confirmed subscription, can receive invite.{' '}
          <strong>Pending</strong> = payment not yet reviewed.{' '}
          <strong>No Subscription</strong> = no paid subscription yet.
          {' '}Update statuses on the Students page.
        </InfoTooltip>
      </div>

      {/* Stats Section */}
      <div className="bg-surface shadow-card rounded-[var(--radius-lg)] p-4 mb-6 space-y-3">
        {/* Progress bar */}
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold text-charcoal whitespace-nowrap">
            {stats.linked} / {total} parents linked
          </span>
          <div className="flex-1 h-2 rounded-full bg-background overflow-hidden">
            <div
              className="h-full bg-mint-green rounded-full transition-all duration-500"
              style={{ width: `${linkedPct}%` }}
            />
          </div>
          <span className="text-sm font-medium text-text-secondary w-10 text-right">
            {linkedPct}%
          </span>
        </div>

        {/* Count chips — tap to filter */}
        <div className="flex flex-wrap gap-2">
          {(['linked', 'ready', 'pending', 'no_subscription'] as OnboardingStatus[]).map((s) => {
            const count = activeStudents.filter((st) => getOnboardingStatus(st) === s).length;
            const isActive = statusFilter === s;
            const variantColors: Record<OnboardingStatus, string> = {
              linked: 'border-mint-green/60 text-mint-green-dark bg-mint-green/10',
              ready: 'border-soft-yellow/60 text-charcoal bg-soft-yellow/20',
              pending: 'border-sky-blue/60 text-sky-blue-dark bg-sky-blue/10',
              no_subscription: 'border-divider text-text-secondary bg-background',
            };
            return (
              <button
                key={s}
                onClick={() => setStatusFilter(isActive ? 'all' : s)}
                className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-all
                  ${variantColors[s]}
                  ${isActive ? 'ring-2 ring-offset-1 ring-current opacity-100' : 'opacity-70 hover:opacity-100'}`}
              >
                {onboardingStatusLabel[s]}: {count}
              </button>
            );
          })}
        </div>
      </div>

      {/* Filters Row */}
      <div className="space-y-3 mb-4">
        {/* Class filters */}
        {uniqueClassIds.length > 1 && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold text-text-secondary uppercase tracking-wider mr-1">Class:</span>
            <FilterChip
              label="All"
              selected={classFilter === 'all'}
              onClick={() => setClassFilter('all')}
            />
            {uniqueClassIds.map((id) => (
              <FilterChip
                key={id}
                label={classMap.get(id) || id}
                selected={classFilter === id}
                onClick={() => setClassFilter(id)}
                count={activeStudents.filter((s) => s.classId === id).length}
              />
            ))}
          </div>
        )}

      </div>

      {/* Search + Preview Button */}
      <div className="flex items-center gap-3 mb-4">
        <div className="flex-1">
          <SearchInput
            value={search}
            onChange={setSearch}
            placeholder="Search by name, email, or class..."
          />
        </div>
        <Button variant="outline" size="md" onClick={() => setShowPreviewModal(true)}>
          Preview Email
        </Button>
      </div>

      {/* Bulk Action Bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 px-4 py-3 bg-rose-pink/5 border border-rose-pink/20 rounded-[var(--radius-md)]">
          <span className="text-sm font-semibold text-charcoal">
            {selectedIds.size} selected
          </span>
          <Button variant="outline" size="sm" onClick={selectAllEligible}>
            Select All Eligible
          </Button>
          <Button size="sm" onClick={() => setShowSendModal(true)}>
            Send Onboarding Emails
          </Button>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setSelectedIds(new Set())}
          >
            Clear Selection
          </Button>
        </div>
      )}

      {/* Student Table */}
      <DataTable
        columns={columns}
        data={filtered}
        loading={studentsLoading}
        emptyState={
          <EmptyState
            icon={<Icon name="mail" size={40} />}
            title="No students found"
            description="Adjust your filters or search to find students."
          />
        }
      />

      {/* Select All / Bulk Select Helper */}
      {filtered.length > 0 && selectedIds.size === 0 && (
        <div className="flex items-center justify-between mt-3">
          <button
            onClick={toggleSelectAll}
            className="text-sm text-rose-pink hover:underline font-semibold"
          >
            Select all {filtered.length} visible students
          </button>
          <button
            onClick={selectAllEligible}
            className="text-sm text-rose-pink hover:underline font-semibold"
          >
            Select all eligible (confirmed + email + not linked)
          </button>
        </div>
      )}

      {/* Email History Section */}
      <div className="mt-8">
        <h3 className="text-lg font-bold text-charcoal mb-4">Email History</h3>
        {emailsLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="bg-surface shadow-card rounded-[var(--radius-lg)] p-4 animate-pulse">
                <div className="h-4 w-48 bg-background rounded mb-2" />
                <div className="h-4 w-32 bg-background rounded" />
              </div>
            ))}
          </div>
        ) : !emailHistory || emailHistory.length === 0 ? (
          <p className="text-sm text-text-secondary">No emails sent yet</p>
        ) : (
          <div className="space-y-3">
            {emailHistory.map((record: OnboardingEmailRecord) => (
              <div
                key={record.id}
                className="bg-surface shadow-card rounded-[var(--radius-lg)] p-4 flex items-center justify-between"
              >
                <div className="flex items-center gap-4">
                  <div>
                    <p className="text-sm font-semibold text-charcoal">
                      {new Date(record.createdAt).toLocaleDateString(undefined, {
                        year: 'numeric',
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </p>
                    {record.emailSubject && (
                      <p className="text-xs text-text-secondary mt-0.5">{record.emailSubject}</p>
                    )}
                  </div>
                  <Badge variant={emailStatusVariants[record.status] ?? 'default'}>
                    {record.status.charAt(0).toUpperCase() + record.status.slice(1)}
                  </Badge>
                </div>
                <div className="text-sm text-text-secondary">
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
      <SendOnboardingEmailModal
        open={showSendModal}
        onClose={() => setShowSendModal(false)}
        selectedStudentIds={Array.from(selectedIds)}
        students={activeStudents}
        onSuccess={handleSendSuccess}
      />

      <EmailPreviewModal
        open={showPreviewModal}
        onClose={() => setShowPreviewModal(false)}
      />
    </div>
  );
}
