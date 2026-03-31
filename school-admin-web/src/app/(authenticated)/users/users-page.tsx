'use client';

import { useState, useMemo } from 'react';
import { PageHeader } from '@/components/lumi/page-header';
import { Tabs } from '@/components/lumi/tabs';
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
import { useUsers, useDeactivateUser, useReactivateUser, useResetPassword } from '@/lib/hooks/use-users';
import { CreateUserModal } from './create-user-modal';

type SerializedUser = NonNullable<ReturnType<typeof useUsers>['data']>[number];

export function UsersPage() {
  const { toast } = useToast();
  const { user: currentUser } = useAuth();
  const { data: allUsers, isLoading } = useUsers();
  const deactivate = useDeactivateUser();
  const reactivate = useReactivateUser();
  const resetPassword = useResetPassword();

  const [activeTab, setActiveTab] = useState('staff');
  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [deactivateConfirm, setDeactivateConfirm] = useState<string | null>(null);
  const [resetConfirm, setResetConfirm] = useState<string | null>(null);

  const staff = useMemo(() => {
    if (!allUsers) return [];
    return allUsers.filter((u) => u.role === 'teacher' || u.role === 'schoolAdmin');
  }, [allUsers]);

  const parents = useMemo(() => {
    if (!allUsers) return [];
    return allUsers.filter((u) => u.role === 'parent');
  }, [allUsers]);

  const currentList = activeTab === 'staff' ? staff : parents;

  const filtered = useMemo(() => {
    if (!search.trim()) return currentList;
    const q = search.toLowerCase().trim();
    return currentList.filter(
      (u) =>
        u.fullName.toLowerCase().includes(q) ||
        u.email.toLowerCase().includes(q)
    );
  }, [currentList, search]);

  const tabs = [
    { id: 'staff', label: 'Staff', count: staff.length, icon: <Icon name="group" size={18} /> },
    { id: 'parents', label: 'Parents', count: parents.length, icon: <Icon name="family_restroom" size={18} /> },
  ];

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
        return (
          <div className="flex gap-1" onClick={(e) => e.stopPropagation()}>
            {row.role !== 'parent' && (
              <Button variant="ghost" size="sm" onClick={() => setResetConfirm(row.id)}>
                Reset PW
              </Button>
            )}
            {row.isActive ? (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setDeactivateConfirm(row.id)}
                className="text-error hover:text-error"
              >
                Deactivate
              </Button>
            ) : (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => handleReactivate(row.id)}
                className="text-mint-green-dark"
              >
                Reactivate
              </Button>
            )}
          </div>
        );
      },
      className: 'text-right',
    },
  ];

  const parentColumns: DataTableColumn<SerializedUser>[] = [
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
      id: 'created',
      header: 'Joined',
      accessorFn: (row) => row.createdAt,
      cell: (value) => new Date(value as string).toLocaleDateString(),
      sortable: true,
    },
  ];

  return (
    <div>
      <PageHeader
        title="Users"
        description="Manage school staff and parents"
        action={
          isAdmin ? (
            <Button onClick={() => setShowCreate(true)}>
              Add Staff Member
            </Button>
          ) : undefined
        }
      />

      <Tabs tabs={tabs} activeTab={activeTab} onChange={setActiveTab} />

      <div className="mt-4 mb-4">
        <SearchInput value={search} onChange={setSearch} placeholder="Search by name or email..." />
      </div>

      <DataTable
        columns={activeTab === 'staff' ? staffColumns : parentColumns}
        data={filtered}
        loading={isLoading}
        emptyState={
          <EmptyState
            icon={activeTab === 'staff' ? <Icon name="group" size={40} /> : <Icon name="family_restroom" size={40} />}
            title={search ? 'No users found' : `No ${activeTab === 'staff' ? 'staff members' : 'parents'}`}
            description={
              activeTab === 'staff' && isAdmin
                ? 'Add staff members to get started.'
                : activeTab === 'parents'
                ? 'Parents will appear here once they link via codes.'
                : undefined
            }
            action={activeTab === 'staff' && isAdmin ? <Button onClick={() => setShowCreate(true)}>Add Staff Member</Button> : undefined}
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
    </div>
  );
}
