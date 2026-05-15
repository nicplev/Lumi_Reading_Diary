"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { formatDate } from "@/lib/utils";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";

interface SchoolUsersTabProps {
  schoolId: string;
  users: SchoolUserListItem[];
}

export function SchoolUsersTab({ schoolId, users }: SchoolUsersTabProps) {
  const router = useRouter();
  const [createOpen, setCreateOpen] = useState(false);
  const [editUser, setEditUser] = useState<SchoolUserListItem | null>(null);
  const [authAction, setAuthAction] = useState<{
    user: SchoolUserListItem;
    action: "disable" | "enable" | "resetPassword";
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Create form state
  const [newEmail, setNewEmail] = useState("");
  const [newFullName, setNewFullName] = useState("");
  const [newRole, setNewRole] = useState<string>("");

  // Edit form state
  const [editFullName, setEditFullName] = useState("");
  const [editRole, setEditRole] = useState<string>("");

  const handleCreate = async () => {
    if (!newEmail || !newFullName || !newRole) {
      setError("All fields are required");
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/schools/${schoolId}/users`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: newEmail,
          fullName: newFullName,
          role: newRole,
        }),
      });
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to create user");
      }
      setCreateOpen(false);
      setNewEmail("");
      setNewFullName("");
      setNewRole("");
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleEdit = async () => {
    if (!editUser) return;
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/users/${editUser.id}`,
        {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            fullName: editFullName,
            role: editRole,
          }),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to update user");
      }
      setEditUser(null);
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleAuthAction = async () => {
    if (!authAction) return;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/users/${authAction.user.id}/auth`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: authAction.action }),
        }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to perform action");
      }
      setAuthAction(null);
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleDeactivate = async (user: SchoolUserListItem) => {
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${schoolId}/users/${user.id}`,
        { method: "DELETE" }
      );
      if (!res.ok) {
        const err = await res.json();
        throw new Error(err.error || "Failed to deactivate user");
      }
      router.refresh();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  const [deactivateUser, setDeactivateUser] =
    useState<SchoolUserListItem | null>(null);

  const columns: ColumnDef<SchoolUserListItem, unknown>[] = [
    {
      accessorKey: "fullName",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
    },
    {
      accessorKey: "email",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Email" />
      ),
    },
    {
      accessorKey: "role",
      header: "Role",
      cell: ({ row }) => <StatusBadge status={row.original.role} />,
    },
    {
      accessorKey: "lastLoginAt",
      header: "Last Login",
      cell: ({ row }) => formatDate(row.original.lastLoginAt),
    },
    {
      accessorKey: "isActive",
      header: "Status",
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.isActive ? "active" : "disabled"}
        />
      ),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        const user = row.original;
        return (
          <div className="flex gap-1">
            <Button
              variant="ghost"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                setEditUser(user);
                setEditFullName(user.fullName);
                setEditRole(user.role);
                setError(null);
              }}
            >
              Edit
            </Button>
            {user.isActive ? (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  setAuthAction({ user, action: "disable" });
                }}
              >
                Disable
              </Button>
            ) : (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  setAuthAction({ user, action: "enable" });
                }}
              >
                Enable
              </Button>
            )}
            <Button
              variant="ghost"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                setAuthAction({ user, action: "resetPassword" });
              }}
            >
              Reset PW
            </Button>
            {user.isActive && (
              <Button
                variant="ghost"
                size="sm"
                className="text-destructive"
                onClick={(e) => {
                  e.stopPropagation();
                  setDeactivateUser(user);
                }}
              >
                Deactivate
              </Button>
            )}
          </div>
        );
      },
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Users</h3>
        <Dialog open={createOpen} onOpenChange={setCreateOpen}>
          <DialogTrigger render={<Button />}>
            <Plus className="mr-2 h-4 w-4" />
            Add User
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Add User</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 pt-4">
              {error && (
                <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
                  {error}
                </div>
              )}
              <div className="space-y-2">
                <Label>Email *</Label>
                <Input
                  type="email"
                  value={newEmail}
                  onChange={(e) => setNewEmail(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>Full Name *</Label>
                <Input
                  value={newFullName}
                  onChange={(e) => setNewFullName(e.target.value)}
                />
              </div>
              <div className="space-y-2">
                <Label>Role *</Label>
                <Select value={newRole} onValueChange={(v) => v && setNewRole(v)}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select role" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="teacher">Teacher</SelectItem>
                    <SelectItem value="schoolAdmin">School Admin</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="flex justify-end gap-2 pt-2">
                <Button variant="outline" onClick={() => setCreateOpen(false)}>
                  Cancel
                </Button>
                <Button onClick={handleCreate} disabled={loading}>
                  {loading ? "Creating..." : "Create"}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>

      <DataTable
        columns={columns}
        data={users}
        searchKey="fullName"
        searchPlaceholder="Search users..."
      />

      {/* Edit Dialog */}
      <Dialog
        open={!!editUser}
        onOpenChange={(open) => {
          if (!open) setEditUser(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit User</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            {error && (
              <div className="rounded-md bg-destructive/10 p-3 text-sm text-destructive">
                {error}
              </div>
            )}
            <div className="space-y-2">
              <Label>Full Name</Label>
              <Input
                value={editFullName}
                onChange={(e) => setEditFullName(e.target.value)}
              />
            </div>
            <div className="space-y-2">
              <Label>Role</Label>
              <Select
                value={editRole}
                onValueChange={(v) => v && setEditRole(v)}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="teacher">Teacher</SelectItem>
                  <SelectItem value="schoolAdmin">School Admin</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="outline" onClick={() => setEditUser(null)}>
                Cancel
              </Button>
              <Button onClick={handleEdit} disabled={loading}>
                {loading ? "Saving..." : "Save"}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>

      {/* Auth Action Confirm */}
      <ConfirmDialog
        open={!!authAction}
        onOpenChange={(open) => {
          if (!open) setAuthAction(null);
        }}
        title={
          authAction?.action === "disable"
            ? "Disable User"
            : authAction?.action === "enable"
              ? "Enable User"
              : "Reset Password"
        }
        description={
          authAction?.action === "disable"
            ? `Disable Firebase Auth for ${authAction.user.fullName}? They will not be able to sign in.`
            : authAction?.action === "enable"
              ? `Re-enable Firebase Auth for ${authAction?.user.fullName}?`
              : `Generate a password reset link for ${authAction?.user.fullName}?`
        }
        confirmLabel={
          authAction?.action === "disable"
            ? "Disable"
            : authAction?.action === "enable"
              ? "Enable"
              : "Reset"
        }
        variant={authAction?.action === "disable" ? "destructive" : "default"}
        onConfirm={handleAuthAction}
        loading={loading}
      />

      {/* Deactivate Confirm */}
      <ConfirmDialog
        open={!!deactivateUser}
        onOpenChange={(open) => {
          if (!open) setDeactivateUser(null);
        }}
        title="Deactivate User"
        description={`Deactivate ${deactivateUser?.fullName}? This will mark them as inactive in this school.`}
        confirmLabel="Deactivate"
        variant="destructive"
        onConfirm={() => {
          if (deactivateUser) {
            handleDeactivate(deactivateUser);
            setDeactivateUser(null);
          }
        }}
        loading={loading}
      />
    </div>
  );
}
