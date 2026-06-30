'use client';

import { useState, useMemo, useEffect } from 'react';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { StatusEditorBadge } from '@/components/lumi/status-editor-badge';
import { FilterChip } from '@/components/lumi/filter-chip';
import { SearchInput } from '@/components/lumi/search-input';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { InfoTooltip } from '@/components/lumi/tooltip';
import { useToast } from '@/components/lumi/toast';
import { useStudents, useUpdateEnrollmentStatus, useBulkUpdateEnrollmentStatus } from '@/lib/hooks/use-students';
import { useClasses } from '@/lib/hooks/use-classes';
import { useOnboardingEmails, type OnboardingEmailRecord } from '@/lib/hooks/use-onboarding-emails';
import { SendOnboardingEmailModal } from './send-onboarding-email-modal';
import { EmailPreviewModal } from './email-preview-modal';
import { OnboardingTour } from './onboarding-tour';
import { useAuth } from '@/lib/auth/auth-context';
import type { EnrollmentStatus } from '@/lib/types';

type OnboardingStatus = 'linked' | 'ready' | 'no_subscription';

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
  return 'ready'; // book_pack or direct_purchase, not yet linked
}

const onboardingStatusLabel: Record<OnboardingStatus, string> = {
  linked: 'Linked',
  // "Subscribed" (not "Ready") so the filter chip matches the editable row
  // badge — a subscribed, not-yet-linked student is the one ready to invite.
  ready: 'Subscribed',
  no_subscription: 'Not Subscribed',
};

const onboardingStatusVariant: Record<OnboardingStatus, 'success' | 'warning' | 'default'> = {
  linked: 'success',
  ready: 'warning',
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
  const { user } = useAuth();
  const { data: students, isLoading: studentsLoading } = useStudents();
  const { data: classes } = useClasses();
  const { data: emailHistory, isLoading: emailsLoading } = useOnboardingEmails();
  const updateEnrollment = useUpdateEnrollmentStatus();
  const bulkUpdateEnrollment = useBulkUpdateEnrollmentStatus();

  const classMap = useMemo(() => {
    if (!classes) return new Map<string, string>();
    return new Map(classes.map((c) => [c.id, c.name]));
  }, [classes]);

  const [search, setSearch] = useState('');
  const [classFilter, setClassFilter] = useState<string>('all');
  // Default to "To onboard" (everyone not yet linked) so staff can mark paying
  // students Subscribed inline AND send invites from one page. Already-linked
  // (onboarded) students are hidden by default — one tap away via All/Linked.
  const [statusFilter, setStatusFilter] = useState<OnboardingStatus | 'all' | 'unlinked'>('unlinked');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [showSendModal, setShowSendModal] = useState(false);
  const [showPreviewModal, setShowPreviewModal] = useState(false);
  const [runTour, setRunTour] = useState(false);

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
      .filter((s) => {
        if (statusFilter === 'all') return true;
        const st = getOnboardingStatus(s);
        // "unlinked" = the to-onboard pipeline (Ready + Not Subscribed).
        if (statusFilter === 'unlinked') return st !== 'linked';
        return st === statusFilter;
      })
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

  // Selected students who can actually be marked subscribed (currently not
  // subscribed and not linked). Drives whether the bulk "Mark Subscribed"
  // action shows — already-subscribed selections don't get the option again.
  const selectedNotSubscribedIds = useMemo(
    () =>
      activeStudents
        .filter((s) => selectedIds.has(s.id) && getOnboardingStatus(s) === 'no_subscription')
        .map((s) => s.id),
    [activeStudents, selectedIds],
  );

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

  // Inline subscription edit — lets staff mark paying students Subscribed
  // without leaving this page; the row re-renders as "Ready" once it lands.
  const handleEnrollmentChange = async (student: StudentRow, status: EnrollmentStatus) => {
    try {
      await updateEnrollment.mutateAsync({ studentId: student.id, enrollmentStatus: status });
      toast(
        `${student.firstName} marked ${status === 'not_enrolled' ? 'Not Subscribed' : 'Subscribed'}`,
        'success',
      );
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update status', 'error');
    }
  };

  const handleBulkMarkSubscribed = async () => {
    const ids = selectedNotSubscribedIds;
    if (ids.length === 0) return;
    try {
      await bulkUpdateEnrollment.mutateAsync({ studentIds: ids, enrollmentStatus: 'book_pack' });
      toast(`${ids.length} student${ids.length !== 1 ? 's' : ''} marked Subscribed`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to update status', 'error');
    }
  };

  // Product tour: auto-launch once per user (persisted in localStorage), and a
  // "Take a tour" button replays it. Wait for the table to load so step targets
  // exist before the tour starts.
  const tourSeenKey = user?.uid ? `lumi:tour:parent-onboarding:${user.uid}` : null;

  useEffect(() => {
    if (!tourSeenKey || studentsLoading) return;
    if (!localStorage.getItem(tourSeenKey)) {
      setRunTour(true);
    }
  }, [tourSeenKey, studentsLoading]);

  const handleTourClose = () => {
    setRunTour(false);
    if (tourSeenKey) localStorage.setItem(tourSeenKey, '1');
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
          className="w-4 h-4 rounded border-rule text-section focus:ring-section/30 cursor-pointer"
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
          <span className="text-sm text-ink">{value as string}</span>
        ) : (
          <span className="text-sm text-muted/50 italic">No email</span>
        ),
      sortable: true,
    },
    {
      id: 'status',
      header: 'Status',
      accessorFn: (row) => getOnboardingStatus(row),
      cell: (value, row) => {
        // Linked students are done — static badge. Everyone else gets the
        // editable subscription control, so staff can mark paying students
        // Subscribed right here (they then become "Ready" to invite).
        if ((value as OnboardingStatus) === 'linked') {
          return (
            <Badge variant={onboardingStatusVariant.linked}>
              {onboardingStatusLabel.linked}
            </Badge>
          );
        }
        return (
          <StatusEditorBadge
            status={row.enrollmentStatus}
            onChange={(next) => handleEnrollmentChange(row, next)}
          />
        );
      },
    },
  ];

  if (studentsLoading) {
    return (
      <div className="space-y-4">
        <div className="bg-paper shadow-card rounded-[var(--radius-lg)] p-4 animate-pulse">
          <div className="h-4 w-48 bg-cream rounded mb-3" />
          <div className="h-2 w-full bg-cream rounded mb-4" />
          <div className="flex gap-3">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="h-8 w-28 bg-cream rounded-full" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  const total = activeStudents.length;
  const linkedPct = total ? Math.round((stats.linked / total) * 100) : 0;

  // The default view hides already-linked students, so an empty table usually
  // means "nothing left to onboard" rather than "no data" — show a reassuring
  // state with a way back to everyone.
  const tableEmptyState =
    (statusFilter === 'unlinked' || statusFilter === 'ready') && !search.trim() ? (
      <EmptyState
        icon={<Icon name="task_alt" size={40} />}
        title="No students waiting to be onboarded"
        description="Already-linked students are hidden here. Switch to All or Linked to view them or re-send an invite."
        action={
          total > 0 ? (
            <Button variant="outline" size="sm" onClick={() => setStatusFilter('all')}>
              Show all {total} students
            </Button>
          ) : undefined
        }
      />
    ) : (
      <EmptyState
        icon={<Icon name="mail" size={40} />}
        title="No students found"
        description="Adjust your filters or search to find students."
      />
    );

  return (
    <div>
      {/* Status guide (inline tooltip) + tour launcher */}
      <div className="flex items-center justify-between gap-3 mb-4">
        <div className="flex items-center gap-1.5">
          <span className="text-sm font-semibold text-muted">Onboarding Status Guide</span>
          <InfoTooltip>
            <strong>Not Subscribed</strong> = no paid subscription yet.{' '}
            <strong>Subscribed</strong> = paid, ready to receive an invite.{' '}
            <strong>Linked</strong> = parent account connected (done).
            {' '}Mark subscriptions right here, or on the Students page.
          </InfoTooltip>
        </div>
        <button
          type="button"
          data-tour="take-tour"
          onClick={() => setRunTour(true)}
          className="inline-flex items-center gap-1.5 text-sm font-semibold text-section hover:underline shrink-0"
        >
          <Icon name="help" size={16} />
          Take a tour
        </button>
      </div>

      {/* Stats Section */}
      <div className="bg-paper shadow-card rounded-[var(--radius-lg)] p-4 mb-6 space-y-3">
        {/* Progress bar */}
        <div className="flex items-center gap-3">
          <span className="text-sm font-semibold text-ink whitespace-nowrap">
            {stats.linked} / {total} parents linked
          </span>
          <div className="flex-1 h-2 rounded-full bg-cream overflow-hidden">
            <div
              className="h-full bg-lumi-green rounded-full transition-all duration-500"
              style={{ width: `${linkedPct}%` }}
            />
          </div>
          <span className="text-sm font-medium text-muted w-10 text-right">
            {linkedPct}%
          </span>
        </div>

        {/* Count chips — tap to filter. Defaults to "To onboard" (not yet linked). */}
        <div className="space-y-2" data-tour="status-chips">
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => setStatusFilter('unlinked')}
              className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-all border-section/50 text-section-strong bg-section/10
                ${statusFilter === 'unlinked' ? 'ring-2 ring-offset-1 ring-section opacity-100' : 'opacity-70 hover:opacity-100'}`}
            >
              To onboard: {activeStudents.filter((st) => getOnboardingStatus(st) !== 'linked').length}
            </button>
            {(['ready', 'no_subscription', 'linked'] as OnboardingStatus[]).map((s) => {
              const count = activeStudents.filter((st) => getOnboardingStatus(st) === s).length;
              const isActive = statusFilter === s;
              const variantColors: Record<OnboardingStatus, string> = {
                linked: 'border-lumi-green/60 text-lumi-green-dark bg-lumi-green/10',
                ready: 'border-lumi-yellow/60 text-ink bg-lumi-yellow/20',
                no_subscription: 'border-rule text-muted bg-cream',
              };
              return (
                <button
                  key={s}
                  onClick={() => setStatusFilter(s)}
                  className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-all
                    ${variantColors[s]}
                    ${isActive ? 'ring-2 ring-offset-1 ring-current opacity-100' : 'opacity-70 hover:opacity-100'}`}
                >
                  {onboardingStatusLabel[s]}: {count}
                </button>
              );
            })}
            <button
              onClick={() => setStatusFilter('all')}
              className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-all border-rule text-ink bg-paper
                ${statusFilter === 'all' ? 'ring-2 ring-offset-1 ring-section opacity-100' : 'opacity-70 hover:opacity-100'}`}
            >
              All: {activeStudents.length}
            </button>
          </div>
          {statusFilter === 'unlinked' && (
            <p className="text-xs text-muted">
              Mark paying students <span className="font-semibold text-ink">Subscribed</span> (tap their status), then select them and <span className="font-semibold text-ink">Send Onboarding Emails</span> — all here. Already-linked students are hidden; tap <span className="font-semibold text-ink">Linked</span> to re-send.
            </p>
          )}
        </div>
      </div>

      {/* Filters Row */}
      <div className="space-y-3 mb-4">
        {/* Class filters */}
        {uniqueClassIds.length > 1 && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold text-muted uppercase tracking-wider mr-1">Class:</span>
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
        <Button variant="outline" size="md" data-tour="preview-email" onClick={() => setShowPreviewModal(true)}>
          Preview Email
        </Button>
      </div>

      {/* Bulk Action Bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 mb-4 px-4 py-3 bg-section/5 border border-section/20 rounded-[var(--radius-md)]">
          <span className="text-sm font-semibold text-ink">
            {selectedIds.size} selected
          </span>
          <Button variant="outline" size="sm" onClick={selectAllEligible}>
            Select All Eligible
          </Button>
          {selectedNotSubscribedIds.length > 0 && (
            <Button
              variant="secondary"
              size="sm"
              onClick={handleBulkMarkSubscribed}
              loading={bulkUpdateEnrollment.isPending}
            >
              Mark {selectedNotSubscribedIds.length} Subscribed
            </Button>
          )}
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
      <div data-tour="student-table">
        <DataTable
          columns={columns}
          data={filtered}
          loading={studentsLoading}
          emptyState={tableEmptyState}
        />
      </div>

      {/* Select All / Bulk Select Helper */}
      {filtered.length > 0 && selectedIds.size === 0 && (
        <div className="flex items-center justify-between mt-3">
          <button
            onClick={toggleSelectAll}
            className="text-sm text-section hover:underline font-semibold"
          >
            Select all {filtered.length} visible students
          </button>
          <button
            onClick={selectAllEligible}
            className="text-sm text-section hover:underline font-semibold"
          >
            Select all eligible (subscribed + email + not linked)
          </button>
        </div>
      )}

      {/* Email History Section */}
      <div className="mt-8">
        <h3 className="text-lg font-bold text-ink mb-4">Email History</h3>
        {emailsLoading ? (
          <div className="space-y-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="bg-paper shadow-card rounded-[var(--radius-lg)] p-4 animate-pulse">
                <div className="h-4 w-48 bg-cream rounded mb-2" />
                <div className="h-4 w-32 bg-cream rounded" />
              </div>
            ))}
          </div>
        ) : !emailHistory || emailHistory.length === 0 ? (
          <p className="text-sm text-muted">No emails sent yet</p>
        ) : (
          <div className="space-y-3">
            {emailHistory.map((record: OnboardingEmailRecord) => (
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
                    {record.emailSubject && (
                      <p className="text-xs text-muted mt-0.5">{record.emailSubject}</p>
                    )}
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

      <OnboardingTour run={runTour} onClose={handleTourClose} />

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
