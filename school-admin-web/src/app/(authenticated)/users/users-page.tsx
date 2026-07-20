'use client';

import { useState, useMemo, useEffect } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Avatar } from '@/components/lumi/avatar';
import { SearchInput } from '@/components/lumi/search-input';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { Tabs } from '@/components/lumi/tabs';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { useAuth } from '@/lib/auth/auth-context';
import { useUsers, useDeactivateUser, useReactivateUser, useResetPassword, useMarkUserForDeletion, useUndoDeleteUser } from '@/lib/hooks/use-users';
import { useSchoolCode, useRotateSchoolCode, type SerializedSchoolCode } from '@/lib/hooks/use-school-code';
import { KebabMenu } from '@/components/lumi/kebab-menu';
import { CreateUserModal } from './create-user-modal';
import { BulkImportStaffModal } from './bulk-import-staff-modal';
import { ViewCredentialsModal } from './view-credentials-modal';
import { StaffOnboardingTab } from './staff-onboarding-tab';

type SerializedUser = NonNullable<ReturnType<typeof useUsers>['data']>[number];

/** A temp password is "pending" while it's been issued and the staff member
 *  hasn't logged in since — mirrors the server's isTempPasswordPending. */
function hasPendingTempPassword(u: SerializedUser): boolean {
  if (!u.tempPasswordCreatedAt) return false;
  if (!u.lastLoginAt) return true;
  return new Date(u.lastLoginAt) < new Date(u.tempPasswordCreatedAt);
}

export function UsersPage() {
  const { toast } = useToast();
  const { user: currentUser } = useAuth();
  const { data: allUsers, isLoading } = useUsers();
  const { data: schoolCode } = useSchoolCode();
  const rotateCode = useRotateSchoolCode();
  const deactivate = useDeactivateUser();
  const reactivate = useReactivateUser();
  const resetPassword = useResetPassword();
  const markForDeletion = useMarkUserForDeletion();
  const undoDelete = useUndoDeleteUser();

  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [showImport, setShowImport] = useState(false);
  const [credentialsUser, setCredentialsUser] = useState<SerializedUser | null>(null);
  const [deactivateConfirm, setDeactivateConfirm] = useState<string | null>(null);
  const [resetConfirm, setResetConfirm] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<SerializedUser | null>(null);
  const [rotateConfirm, setRotateConfirm] = useState(false);
  const [codeCopied, setCodeCopied] = useState(false);
  const [tab, setTab] = useState<'staff' | 'onboarding'>('staff');
  // Deep-link from the dashboard's "staff haven't signed in yet" attention row.
  const [pendingOnly, setPendingOnly] = useState(false);
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get('filter') === 'pending') {
      setPendingOnly(true);
      setTab('staff');
    }
  }, []);

  const staff = useMemo(() => {
    if (!allUsers) return [];
    return allUsers.filter((u) => u.role === 'teacher' || u.role === 'schoolAdmin');
  }, [allUsers]);

  const filtered = useMemo(() => {
    let list = staff;
    if (pendingOnly) list = list.filter(hasPendingTempPassword);
    if (search.trim()) {
      const q = search.toLowerCase().trim();
      list = list.filter(
        (u) =>
          u.fullName.toLowerCase().includes(q) ||
          u.email.toLowerCase().includes(q)
      );
    }
    return list;
  }, [staff, search, pendingOnly]);

  const handleDeactivate = async () => {
    if (!deactivateConfirm) return;
    try {
      await deactivate.mutateAsync(deactivateConfirm);
      toast('User deactivated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to deactivate', 'error');
    }
    setDeactivateConfirm(null);
  };

  const handleReactivate = async (userId: string) => {
    try {
      await reactivate.mutateAsync(userId);
      toast('User reactivated', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to reactivate', 'error');
    }
  };

  const handleDelete = async () => {
    if (!deleteConfirm) return;
    try {
      await markForDeletion.mutateAsync(deleteConfirm.id);
      toast(`${deleteConfirm.fullName} scheduled for deletion in 24 hours`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to schedule deletion', 'error');
    }
    setDeleteConfirm(null);
  };

  const handleUndoDelete = async (userId: string) => {
    try {
      await undoDelete.mutateAsync(userId);
      toast('Deletion cancelled', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to cancel deletion', 'error');
    }
  };

  const handleCopyCode = async () => {
    if (!schoolCode?.code) return;
    try {
      await navigator.clipboard.writeText(schoolCode.code);
      setCodeCopied(true);
      setTimeout(() => setCodeCopied(false), 2000);
      toast('Code copied to clipboard', 'success');
    } catch {
      toast('Failed to copy code', 'error');
    }
  };

  const handleRotate = async () => {
    try {
      const result = await rotateCode.mutateAsync();
      toast(`New staff code: ${result.code}`, 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to rotate code', 'error');
    }
    setRotateConfirm(false);
  };

  const handleResetPassword = async () => {
    if (!resetConfirm) return;
    try {
      const result = await resetPassword.mutateAsync(resetConfirm);
      await navigator.clipboard.writeText(result.link);
      toast('Password reset link copied to clipboard', 'success');
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Failed to reset password', 'error');
    }
    setResetConfirm(null);
  };

  const isAdmin = currentUser?.role === 'schoolAdmin';

  const staffColumns: DataTableColumn<SerializedUser>[] = [
    {
      id: 'name',
      header: 'Name',
      accessorFn: (row) => row.fullName,
      cell: (value, row) => (
        <div className="flex items-center gap-3">
          <Avatar name={value as string} characterId={row.characterId} size="sm" />
          <div>
            <div className="flex items-center gap-2">
              <p className="font-semibold text-ink">{value as string}</p>
              {isAdmin && hasPendingTempPassword(row) && (
                <Badge variant="warning">Temp password</Badge>
              )}
            </div>
            <p className="text-xs text-muted">{row.email}</p>
          </div>
        </div>
      ),
      sortable: true,
    },
    {
      id: 'role',
      header: 'Role',
      accessorFn: (row) => row.role,
      cell: (value) => (
        <Badge variant={value === 'schoolAdmin' ? 'info' : 'success'}>
          {value === 'schoolAdmin' ? 'Admin' : 'Teacher'}
        </Badge>
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
      cell: (value) => value ? new Date(value as string).toLocaleDateString() : 'Never',
      sortable: true,
    },
    {
      id: 'actions',
      header: '',
      accessorFn: (row) => row.id,
      cell: (_, row) => {
        if (row.id === currentUser?.uid) {
          return <Badge variant="default">You</Badge>;
        }
        if (!isAdmin) return null;

        if (row.pendingDeletion) {
          const hoursLeft = row.scheduledDeletionAt
            ? Math.max(0, Math.ceil((new Date(row.scheduledDeletionAt).getTime() - Date.now()) / (1000 * 60 * 60)))
            : 24;
          return (
            <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
              <Badge variant="warning">Deleting in {hoursLeft}h</Badge>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => handleUndoDelete(row.id)}
                className="text-amber-600 hover:text-amber-700"
              >
                Undo Delete
              </Button>
            </div>
          );
        }

        const credentialsItem = hasPendingTempPassword(row)
          ? [{ label: 'View login credentials', onClick: () => setCredentialsUser(row) }]
          : [];

        return (
          <KebabMenu
            items={row.isActive
              ? [
                  ...credentialsItem,
                  { label: 'Reset Password', onClick: () => setResetConfirm(row.id) },
                  { label: 'Deactivate', onClick: () => setDeactivateConfirm(row.id), variant: 'danger' },
                ]
              : [
                  { label: 'Reset Password', onClick: () => setResetConfirm(row.id) },
                  { label: 'Reactivate', onClick: () => handleReactivate(row.id) },
                  { label: 'Delete', onClick: () => setDeleteConfirm(row), variant: 'danger' },
                ]
            }
          />
        );
      },
      className: 'text-right',
    },
  ];

  return (
    <div>
      <PageHeader
        eyebrow="Staff"
        title="Staff"
        description="Manage school staff"
        action={
          isAdmin ? (
            <div className="flex items-center gap-2">
              <Button variant="outline" onClick={() => setShowImport(true)}>
                Import Staff
              </Button>
              <Button onClick={() => setShowCreate(true)}>
                Add Staff Member
              </Button>
            </div>
          ) : undefined
        }
      />

      <div className="mb-4 flex items-center gap-3 text-sm" title="New teachers and admins enter this code when creating an account in the Lumi mobile app.">
        <span className="text-xs font-semibold uppercase tracking-wide text-muted">Staff code</span>
        <code className="bg-cream border border-border px-2 py-1 rounded font-mono font-bold text-ink tracking-wider">
          {schoolCode?.code ?? '—'}
        </code>
        {schoolCode?.code && (
          <button
            onClick={handleCopyCode}
            className="text-muted hover:text-ink transition-colors"
            title="Copy code"
          >
            {codeCopied ? (
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M3 7l3 3 5-5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>
            ) : (
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><rect x="4" y="4" width="8" height="8" rx="1.5" stroke="currentColor" strokeWidth="1.2" /><path d="M10 4V3a1.5 1.5 0 00-1.5-1.5H3A1.5 1.5 0 001.5 3v5.5A1.5 1.5 0 003 10h1" stroke="currentColor" strokeWidth="1.2" /></svg>
            )}
          </button>
        )}
        {schoolCode?.code && <SchoolCodeValidity code={schoolCode} />}
        {isAdmin && (
          <button
            onClick={() => setRotateConfirm(true)}
            className="text-xs text-muted hover:text-ink underline underline-offset-2"
          >
            {schoolCode?.code ? 'Change' : 'Generate'}
          </button>
        )}
      </div>

      {schoolCode?.code && (
        <SchoolCodeExpiredNotice code={schoolCode} isAdmin={isAdmin} />
      )}

      {isAdmin && (
        <Tabs
          tabs={[
            { id: 'staff', label: 'Staff' },
            { id: 'onboarding', label: 'Onboarding' },
          ]}
          activeTab={tab}
          onChange={(id) => setTab(id as 'staff' | 'onboarding')}
        />
      )}

      {isAdmin && tab === 'onboarding' ? (
        <StaffOnboardingTab />
      ) : (
        <>
          {pendingOnly && (
            <div className="mb-4 inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-section/10 text-sm font-semibold text-section-strong">
              <Icon name="filter_alt" size={16} />
              Showing staff who haven&apos;t signed in yet
              <button onClick={() => setPendingOnly(false)} aria-label="Clear filter" className="hover:text-ink leading-none">
                <Icon name="close" size={16} />
              </button>
            </div>
          )}

          <div className="mb-4">
            <SearchInput value={search} onChange={setSearch} placeholder="Search by name or email..." />
          </div>

          <DataTable
            columns={staffColumns}
            data={filtered}
            loading={isLoading}
            emptyState={
              <EmptyState
                icon={<Icon name="group" size={40} />}
                title={search ? 'No users found' : 'No staff members'}
                description={isAdmin ? 'Add staff members to get started.' : undefined}
                action={isAdmin ? <Button onClick={() => setShowCreate(true)}>Add Staff Member</Button> : undefined}
              />
            }
          />
        </>
      )}

      {isAdmin && (
        <>
          <CreateUserModal
            open={showCreate}
            onClose={() => setShowCreate(false)}
          />
          <BulkImportStaffModal
            open={showImport}
            onClose={() => setShowImport(false)}
          />
          <ViewCredentialsModal
            open={!!credentialsUser}
            onClose={() => setCredentialsUser(null)}
            user={credentialsUser ? { id: credentialsUser.id, fullName: credentialsUser.fullName, email: credentialsUser.email } : null}
          />
        </>
      )}

      <ConfirmDialog
        open={!!deactivateConfirm}
        onClose={() => setDeactivateConfirm(null)}
        onConfirm={handleDeactivate}
        title="Deactivate User"
        description="This user will no longer be able to sign in. Their data will be preserved."
        confirmLabel="Deactivate"
        variant="danger"
        loading={deactivate.isPending}
      />

      <ConfirmDialog
        open={!!resetConfirm}
        onClose={() => setResetConfirm(null)}
        onConfirm={handleResetPassword}
        title="Reset Password"
        description="A password reset link will be generated and copied to your clipboard. Share it with the user."
        confirmLabel="Generate Reset Link"
        variant="warning"
        loading={resetPassword.isPending}
      />

      <ConfirmDialog
        open={!!deleteConfirm}
        onClose={() => setDeleteConfirm(null)}
        onConfirm={handleDelete}
        title="Delete User"
        description={`Permanently delete ${deleteConfirm?.fullName ?? 'this user'}? Their account and data will be removed in 24 hours. You can undo this within that window.`}
        confirmLabel="Schedule Deletion"
        variant="danger"
        loading={markForDeletion.isPending}
      />

      <ConfirmDialog
        open={rotateConfirm}
        onClose={() => setRotateConfirm(false)}
        onConfirm={handleRotate}
        title={schoolCode?.code ? 'Change Staff Linking Code' : 'Generate Staff Linking Code'}
        description="Generate a new code for staff signups. Existing teachers and admins will NOT be affected — they remain signed in and linked to the school. The current code (if any) will stop working for new registrations immediately."
        confirmLabel="Generate New Code"
        variant="warning"
        loading={rotateCode.isPending}
      />
    </div>
  );
}

// ── Staff code validity ───────────────────────────────────────────────
// The staff code is enforced server-side on three axes when a teacher
// submits it (functions/src/code_verification.ts): isActive, expiresAt and
// maxUsages. Until now the portal showed none of that, so a code could
// lapse silently and the first anyone knew was a teacher failing to sign
// up. These surface it before that happens.

/**
 * Whole days until `iso`; negative once past. Floors rather than ceils so a
 * code lapsing in two hours reads "Expires today", not "Expires in 1 day" —
 * rounding up would under-warn at exactly the moment warning matters most.
 */
function daysUntil(iso: string): number {
  const ms = new Date(iso).getTime() - Date.now();
  return Math.floor(ms / (24 * 60 * 60 * 1000));
}

function SchoolCodeValidity({ code }: { code: SerializedSchoolCode }) {
  const days = code.expiresAt ? daysUntil(code.expiresAt) : null;
  const usesLeft =
    code.maxUsages != null ? code.maxUsages - code.usageCount : null;

  // Whichever limit bites first is the one worth showing.
  const expired = days != null && days < 0;
  const usedUp = usesLeft != null && usesLeft <= 0;
  const urgent = (days != null && days <= 7) || (usesLeft != null && usesLeft <= 5);

  if (expired || usedUp) {
    // days === -1 covers "lapsed at some point today" (floor puts anything
    // under 24h past into -1), so say that rather than "1 day ago".
    const ago = Math.abs(days ?? 0);
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-red-50 px-2 py-0.5 text-xs font-semibold text-red-700">
        {expired
          ? ago <= 1
            ? 'Expired today'
            : `Expired ${ago} days ago`
          : 'Usage limit reached'}
      </span>
    );
  }

  if (days == null && usesLeft == null) return null;

  // Name whichever limit will bite FIRST. Showing "expires in 20 days" while
  // only 3 signups remain flags the urgency but points at the wrong cause.
  const usesPressing = usesLeft != null && usesLeft <= 5;
  const label =
    usesPressing || days == null
      ? `${usesLeft} ${usesLeft === 1 ? 'use' : 'uses'} left`
      : days === 0
        ? 'Expires today'
        : `Expires in ${days} ${days === 1 ? 'day' : 'days'}`;

  return (
    <span
      className={
        urgent
          ? 'inline-flex items-center gap-1 rounded-full bg-amber-50 px-2 py-0.5 text-xs font-semibold text-amber-700'
          : 'text-xs text-muted'
      }
      title={
        [
          code.expiresAt
            ? `Expires ${new Date(code.expiresAt).toLocaleDateString()}`
            : null,
          usesLeft != null
            ? `Used ${code.usageCount} of ${code.maxUsages} times`
            : null,
        ]
          .filter(Boolean)
          .join(' · ') || undefined
      }
    >
      {label}
    </span>
  );
}

function SchoolCodeExpiredNotice({
  code,
  isAdmin,
}: {
  code: SerializedSchoolCode;
  isAdmin: boolean;
}) {
  const days = code.expiresAt ? daysUntil(code.expiresAt) : null;
  const usesLeft =
    code.maxUsages != null ? code.maxUsages - code.usageCount : null;
  const expired = days != null && days < 0;
  const usedUp = usesLeft != null && usesLeft <= 0;
  if (!expired && !usedUp) return null;

  return (
    <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">
      <strong className="font-semibold">
        This staff code no longer works.
      </strong>{' '}
      {expired
        ? 'It passed its expiry date, so new teachers and admins cannot use it to create an account.'
        : 'It has been used the maximum number of times, so it cannot be used to create new accounts.'}{' '}
      {isAdmin
        ? 'Choose “Change” above to generate a new one — existing staff stay signed in and linked.'
        : 'Ask a school admin to generate a new one.'}
    </div>
  );
}
