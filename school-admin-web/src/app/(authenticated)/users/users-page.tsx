'use client';

import { useState, useMemo } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Button } from '@/components/lumi/button';
import { Badge } from '@/components/lumi/badge';
import { Avatar } from '@/components/lumi/avatar';
import { SearchInput } from '@/components/lumi/search-input';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { useToast } from '@/components/lumi/toast';
import { useAuth } from '@/lib/auth/auth-context';
import { useUsers, useDeactivateUser, useReactivateUser, useResetPassword, useMarkUserForDeletion, useUndoDeleteUser } from '@/lib/hooks/use-users';
import { KebabMenu } from '@/components/lumi/kebab-menu';
import { CreateUserModal } from './create-user-modal';

type SerializedUser = NonNullable<ReturnType<typeof useUsers>['data']>[number];

export function UsersPage() {
  const { toast } = useToast();
  const { user: currentUser } = useAuth();
  const { data: allUsers, isLoading } = useUsers();
  const deactivate = useDeactivateUser();
  const reactivate = useReactivateUser();
  const resetPassword = useResetPassword();
  const markForDeletion = useMarkUserForDeletion();
  const undoDelete = useUndoDeleteUser();

  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [deactivateConfirm, setDeactivateConfirm] = useState<string | null>(null);
  const [resetConfirm, setResetConfirm] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<SerializedUser | null>(null);

  const staff = useMemo(() => {
    if (!allUsers) return [];
    return allUsers.filter((u) => u.role === 'teacher' || u.role === 'schoolAdmin');
  }, [allUsers]);

  const filtered = useMemo(() => {
    if (!search.trim()) return staff;
    const q = search.toLowerCase().trim();
    return staff.filter(
      (u) =>
        u.fullName.toLowerCase().includes(q) ||
        u.email.toLowerCase().includes(q)
    );
  }, [staff, search]);

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
          <Avatar name={value as string} size="sm" />
          <div>
            <p className="font-semibold text-charcoal">{value as string}</p>
            <p className="text-xs text-text-secondary">{row.email}</p>
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

        return (
          <KebabMenu
            items={row.isActive
              ? [
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
        title="Users"
        description="Manage school staff"
        action={
          isAdmin ? (
            <Button onClick={() => setShowCreate(true)}>
              Add Staff Member
            </Button>
          ) : undefined
        }
      />

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

      {isAdmin && (
        <CreateUserModal
          open={showCreate}
          onClose={() => setShowCreate(false)}
        />
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
    </div>
  );
}
