'use client';

import { useState, useMemo } from 'react';
import { Badge } from '@/components/lumi/badge';
import { Button } from '@/components/lumi/button';
import { ConfirmDialog } from '@/components/lumi/confirm-dialog';
import { SearchInput } from '@/components/lumi/search-input';
import { EmptyState } from '@/components/lumi/empty-state';
import { Icon } from '@/components/lumi/icon';
import { KebabMenu } from '@/components/lumi/kebab-menu';
import { Modal } from '@/components/lumi/modal';
import { useToast } from '@/components/lumi/toast';
import { DataTable, type DataTableColumn } from '@/components/lumi/data-table';
import { useAuth } from '@/lib/auth/auth-context';
import { useParents, useUnlinkParentStudent } from '@/lib/hooks/use-parents';
import { useClasses } from '@/lib/hooks/use-classes';

type SerializedParent = NonNullable<ReturnType<typeof useParents>['data']>[number];
type LinkedStudent = SerializedParent['linkedStudents'][number];

interface UnlinkTarget {
  parent: SerializedParent;
  student: LinkedStudent;
}

function studentName(student: LinkedStudent): string {
  return `${student.firstName} ${student.lastName}`.trim();
}

function formatNames(names: string[]): string {
  if (names.length <= 1) return names[0] ?? '';
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  return `${names.slice(0, -1).join(', ')}, and ${names[names.length - 1]}`;
}

export function ParentConnectionsTab() {
  const { user } = useAuth();
  const { toast } = useToast();
  const { data: parents, isLoading } = useParents();
  const { data: classes } = useClasses();
  const unlinkConnection = useUnlinkParentStudent();
  const [search, setSearch] = useState('');
  const [manageParent, setManageParent] = useState<SerializedParent | null>(null);
  const [unlinkTarget, setUnlinkTarget] = useState<UnlinkTarget | null>(null);
  const [unlinkReason, setUnlinkReason] = useState('');

  const classMap = useMemo(() => {
    const map = new Map<string, string>();
    if (classes) {
      for (const c of classes) map.set(c.id, c.name);
    }
    return map;
  }, [classes]);

  const filtered = useMemo(() => {
    if (!parents) return [];
    if (!search.trim()) return parents;

    const q = search.toLowerCase().trim();
    return parents.filter((p) =>
      p.fullName.toLowerCase().includes(q) ||
      p.email.toLowerCase().includes(q) ||
      (p.phoneNumber ?? '').toLowerCase().includes(q) ||
      p.linkedStudents.some((s) =>
        `${s.firstName} ${s.lastName}`.toLowerCase().includes(q)
      )
    );
  }, [parents, search]);

  const requestUnlink = (parent: SerializedParent, student: LinkedStudent) => {
    setManageParent(null);
    setUnlinkReason('');
    setUnlinkTarget({ parent, student });
  };

  const cancelUnlink = () => {
    if (unlinkConnection.isPending) return;
    const parent = unlinkTarget?.parent ?? null;
    setUnlinkTarget(null);
    setUnlinkReason('');
    setManageParent(parent);
  };

  const confirmUnlink = async () => {
    if (!unlinkTarget || !user?.schoolId) return;
    const guardianName = unlinkTarget.parent.fullName;
    const childName = studentName(unlinkTarget.student);
    const reason = unlinkReason.trim();

    try {
      await unlinkConnection.mutateAsync({
        schoolId: user.schoolId,
        parentUserId: unlinkTarget.parent.id,
        studentId: unlinkTarget.student.id,
        ...(reason ? { reason } : {}),
      });
      toast(`${guardianName} was unlinked from ${childName}`, 'success');
      setUnlinkTarget(null);
      setUnlinkReason('');
    } catch (error) {
      toast(
        error instanceof Error ? error.message : 'Failed to unlink this connection',
        'error',
      );
    }
  };

  const unlinkDescription = (() => {
    if (!unlinkTarget) return '';
    const { parent, student } = unlinkTarget;
    const childName = studentName(student);
    const remainingChildren = parent.linkedStudents
      .filter((linked) => linked.id !== student.id)
      .map(studentName);
    const remainingMessage = remainingChildren.length > 0
      ? `Access to ${formatNames(remainingChildren)} will remain unchanged.`
      : 'Their parent account will remain active and they can enter a new invite code later.';
    return `${parent.fullName} will immediately lose access to ${childName}'s profile, reading history, assignments, and future notifications. No student records or reading logs will be deleted. ${remainingMessage}`;
  })();

  const columns: DataTableColumn<SerializedParent>[] = [
    {
      id: 'name',
      header: 'Guardian Name',
      accessorFn: (row) => row.fullName,
      sortable: true,
    },
    {
      id: 'relationship',
      header: 'Relationship',
      accessorFn: (row) => row.relationshipLabel ?? '',
      cell: (value) =>
        value ? (
          <Badge variant="default">{value as string}</Badge>
        ) : (
          <span className="text-muted text-sm">—</span>
        ),
      sortable: true,
    },
    {
      id: 'email',
      header: 'Email/Phone',
      // Prefer email; fall back to phone for parents who registered without one.
      accessorFn: (row) => row.email || row.phoneNumber || '',
      cell: (value) =>
        value ? (
          <span className="text-sm">{value as string}</span>
        ) : (
          <span className="text-sm text-muted">—</span>
        ),
      sortable: true,
    },
    {
      id: 'students',
      header: 'Linked Students',
      accessorFn: (row) => row.linkedStudents.length,
      cell: (_, row) =>
        row.linkedStudents.length === 0 ? (
          <span className="text-muted text-sm">No students linked</span>
        ) : (
          <div className="flex flex-wrap gap-1.5">
            {row.linkedStudents.map((s) => (
              <Badge key={s.id} variant="info">
                {s.firstName} {s.lastName}
                {classMap.get(s.classId) ? ` (${classMap.get(s.classId)})` : ''}
              </Badge>
            ))}
          </div>
        ),
    },
    {
      id: 'status',
      header: 'Status',
      // Sort groups removed (Auth account gone) → inactive → active.
      accessorFn: (row) =>
        row.authMissing ? 'removed' : row.isActive ? 'active' : 'inactive',
      cell: (_, row) =>
        row.authMissing ? (
          <Badge variant="error">Removed</Badge>
        ) : (
          <Badge variant={row.isActive ? 'success' : 'default'}>
            {row.isActive ? 'Active' : 'Inactive'}
          </Badge>
        ),
      sortable: true,
    },
    {
      id: 'lastLogin',
      header: 'Last Login',
      accessorFn: (row) => row.lastLoginAt,
      cell: (value) =>
        value ? (
          <span className="text-sm">{new Date(value as string).toLocaleDateString()}</span>
        ) : (
          <span className="text-sm text-muted">Never</span>
        ),
      sortable: true,
    },
    {
      id: 'created',
      header: 'Joined',
      accessorFn: (row) => row.createdAt,
      cell: (value) => new Date(value as string).toLocaleDateString(),
      sortable: true,
    },
    {
      id: 'actions',
      header: '',
      accessorFn: (row) => row.id,
      cell: (_, row) =>
        row.linkedStudents.length > 0 ? (
          <KebabMenu
            items={[
              {
                label: 'Manage connections',
                onClick: () => setManageParent(row),
              },
            ]}
          />
        ) : (
          <span className="text-muted">—</span>
        ),
      className: 'text-right',
    },
  ];

  return (
    <div>
      <div className="mb-4">
        <SearchInput
          value={search}
          onChange={setSearch}
          placeholder="Search by parent name, email, or student name..."
        />
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        loading={isLoading}
        pageSizeOptions={[10, 20, 50, 100]}
        emptyState={
          <EmptyState
            icon={<Icon name="family_restroom" size={40} />}
            title="No parent accounts"
            description="Parents can register through the mobile app using link codes. Generate codes in the Link Codes tab."
          />
        }
      />

      <Modal
        open={!!manageParent}
        onClose={() => setManageParent(null)}
        title={manageParent ? `Manage ${manageParent.fullName}'s connections` : 'Manage connections'}
        description="Remove one student connection at a time. Guardian accounts and school records are preserved."
        size="md"
        footer={
          <Button variant="outline" onClick={() => setManageParent(null)}>
            Done
          </Button>
        }
      >
        <div className="space-y-3">
          {manageParent && manageParent.linkedStudents.map((student) => {
            const className = classMap.get(student.classId);
            return (
              <div
                key={student.id}
                className="flex items-center justify-between gap-4 rounded-[var(--radius-md)] border border-rule bg-cream/50 px-4 py-3"
              >
                <div className="min-w-0">
                  <p className="font-semibold text-ink truncate">{studentName(student)}</p>
                  <p className="text-sm text-muted truncate">
                    {className || 'No class assigned'}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  className="shrink-0 text-error hover:bg-error/5"
                  onClick={() => requestUnlink(manageParent, student)}
                >
                  Unlink
                </Button>
              </div>
            );
          })}
        </div>
      </Modal>

      <ConfirmDialog
        open={!!unlinkTarget}
        onClose={cancelUnlink}
        onConfirm={confirmUnlink}
        title={
          unlinkTarget
            ? `Unlink ${unlinkTarget.parent.fullName} from ${studentName(unlinkTarget.student)}?`
            : 'Unlink guardian?'
        }
        description={unlinkDescription}
        confirmLabel="Unlink connection"
        variant="danger"
        loading={unlinkConnection.isPending}
      >
        <label htmlFor="unlink-reason" className="block text-sm font-semibold text-ink mb-1.5">
          Reason <span className="font-normal text-muted">(optional)</span>
        </label>
        <textarea
          id="unlink-reason"
          value={unlinkReason}
          onChange={(event) => setUnlinkReason(event.target.value)}
          maxLength={250}
          rows={3}
          placeholder="For example: linked to the wrong guardian"
          className="w-full resize-none rounded-[var(--radius-md)] border border-rule bg-paper px-4 py-3 text-sm text-ink placeholder:text-muted/50 focus:border-section focus:outline-none focus:ring-2 focus:ring-section/30"
        />
        <div className="mt-1 flex justify-between gap-3 text-xs text-muted">
          <span>This note is saved in the administrator audit log.</span>
          <span>{unlinkReason.length}/250</span>
        </div>
      </ConfirmDialog>
    </div>
  );
}
