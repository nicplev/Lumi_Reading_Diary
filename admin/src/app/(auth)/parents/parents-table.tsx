"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { toast } from "sonner";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import type { ParentListItem } from "@/lib/firestore/parents";

interface ParentsTableProps {
  parents: ParentListItem[];
}

// Mirrors ParentAccountPreview from @lumi/server-ops (kept local so this client
// module never reaches into the server-only package).
interface ParentAccountPreview {
  parentId: string;
  schoolId: string;
  fullName?: string;
  email?: string;
  phoneNumber?: string;
  isActive: boolean;
  authExists: boolean;
  authDisabled: boolean;
  mfaPhones: string[];
  linkedChildren: number;
  indexKeys: number;
}

interface DeletionSummary {
  authDeleted: boolean;
  parentDocDeleted: boolean;
  indexDocsDeleted: number;
  studentsUnlinked: number;
  freed: { email?: string; phones: string[] };
}

type SoftAction = "disable" | "enable" | "resetPassword";

export function ParentsTable({ parents }: ParentsTableProps) {
  const router = useRouter();

  const [softAction, setSoftAction] = useState<{
    parent: ParentListItem;
    action: SoftAction;
  } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ParentListItem | null>(null);
  const [preview, setPreview] = useState<ParentAccountPreview | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [loading, setLoading] = useState(false);

  const runSoftAction = async () => {
    if (!softAction) return;
    const { parent, action } = softAction;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${parent.schoolId}/parents/${parent.id}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action }),
        }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Action failed");

      if (action === "resetPassword" && data.resetLink) {
        try {
          await navigator.clipboard.writeText(data.resetLink);
          toast.success("Password reset link copied to clipboard");
        } catch {
          toast.success("Password reset link generated", {
            description: data.resetLink,
          });
        }
      } else {
        toast.success(
          action === "disable"
            ? `${parent.fullName} disabled`
            : `${parent.fullName} re-enabled`
        );
      }
      setSoftAction(null);
      router.refresh();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Action failed");
    } finally {
      setLoading(false);
    }
  };

  const openDelete = async (parent: ParentListItem) => {
    setDeleteTarget(parent);
    setPreview(null);
    setPreviewLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${parent.schoolId}/parents/${parent.id}`
      );
      if (res.ok) {
        setPreview((await res.json()) as ParentAccountPreview);
      }
    } catch {
      // Preview is best-effort; the confirm still works without it.
    } finally {
      setPreviewLoading(false);
    }
  };

  const runDelete = async () => {
    if (!deleteTarget) return;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/schools/${deleteTarget.schoolId}/parents/${deleteTarget.id}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ action: "delete" }),
        }
      );
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || "Delete failed");

      const summary = data.deletion as DeletionSummary | undefined;
      const freedPhone = summary?.freed?.phones?.[0];
      const freedEmail = summary?.freed?.email;
      toast.success(`Deleted ${deleteTarget.fullName}`, {
        description:
          freedEmail || freedPhone
            ? `Freed for reuse: ${[freedEmail, freedPhone]
                .filter(Boolean)
                .join(" · ")}`
            : "Account fully removed",
      });
      setDeleteTarget(null);
      setPreview(null);
      router.refresh();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Delete failed");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<ParentListItem, unknown>[] = [
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
      accessorKey: "linkedChildrenCount",
      header: "Children",
      cell: ({ row }) => row.original.linkedChildrenCount,
    },
    {
      accessorKey: "schoolName",
      header: "School",
      cell: ({ row }) => row.original.schoolName ?? "—",
    },
    {
      accessorKey: "isActive",
      header: "Status",
      cell: ({ row }) => (
        <StatusBadge status={row.original.isActive ? "active" : "disabled"} />
      ),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => {
        const parent = row.original;
        return (
          <div className="flex justify-end gap-1">
            <Button
              variant="ghost"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                setSoftAction({ parent, action: "resetPassword" });
              }}
            >
              Reset PW
            </Button>
            {parent.isActive ? (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  setSoftAction({ parent, action: "disable" });
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
                  setSoftAction({ parent, action: "enable" });
                }}
              >
                Enable
              </Button>
            )}
            <Button
              variant="ghost"
              size="sm"
              className="text-destructive"
              onClick={(e) => {
                e.stopPropagation();
                openDelete(parent);
              }}
            >
              Delete
            </Button>
          </div>
        );
      },
    },
  ];

  return (
    <>
      <DataTable
        columns={columns}
        data={parents}
        searchKey="fullName"
        searchPlaceholder="Search parents..."
        onRowClick={(row) =>
          router.push(`/schools/${row.schoolId}?tab=parents`)
        }
      />

      {/* Disable / Enable / Reset-password confirm */}
      <ConfirmDialog
        open={!!softAction}
        onOpenChange={(open) => {
          if (!open) setSoftAction(null);
        }}
        title={
          softAction?.action === "disable"
            ? "Disable Parent"
            : softAction?.action === "enable"
              ? "Enable Parent"
              : "Reset Password"
        }
        description={
          softAction?.action === "disable"
            ? `Block ${softAction.parent.fullName} from signing in? Their account and data are kept and this can be undone.`
            : softAction?.action === "enable"
              ? `Re-enable sign-in for ${softAction?.parent.fullName}?`
              : `Generate a password reset link for ${softAction?.parent.fullName}? It will be copied to your clipboard.`
        }
        confirmLabel={
          softAction?.action === "disable"
            ? "Disable"
            : softAction?.action === "enable"
              ? "Enable"
              : "Generate link"
        }
        variant={softAction?.action === "disable" ? "destructive" : "default"}
        onConfirm={runSoftAction}
        loading={loading}
      />

      {/* Hard delete (frees email + phone for reuse) */}
      <Dialog
        open={!!deleteTarget}
        onOpenChange={(open) => {
          if (!open) {
            setDeleteTarget(null);
            setPreview(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete parent account</DialogTitle>
            <DialogDescription>
              Permanently removes{" "}
              <span className="font-medium text-foreground">
                {deleteTarget?.fullName}
              </span>{" "}
              from Firebase Auth and Firestore. This frees their email and phone
              so a new account can be created on the same credentials. This
              cannot be undone.
            </DialogDescription>
          </DialogHeader>

          <div className="rounded-md border bg-muted/40 p-3 text-sm">
            {previewLoading ? (
              <p className="text-muted-foreground">Loading account details…</p>
            ) : preview ? (
              <ul className="space-y-1">
                <li>
                  <span className="text-muted-foreground">Email: </span>
                  {preview.email ?? "—"}
                </li>
                <li>
                  <span className="text-muted-foreground">Phone: </span>
                  {preview.phoneNumber ??
                    preview.mfaPhones[0] ??
                    "—"}
                </li>
                <li>
                  <span className="text-muted-foreground">Auth user: </span>
                  {preview.authExists
                    ? preview.authDisabled
                      ? "exists (disabled)"
                      : "exists — will be deleted"
                    : "none (Firestore-only cleanup)"}
                </li>
                <li>
                  <span className="text-muted-foreground">
                    Linked children:{" "}
                  </span>
                  {preview.linkedChildren} (will be unlinked)
                </li>
                <li>
                  <span className="text-muted-foreground">Login index: </span>
                  {preview.indexKeys} entr
                  {preview.indexKeys === 1 ? "y" : "ies"} to remove
                </li>
              </ul>
            ) : (
              <p className="text-muted-foreground">
                Could not load account details — the delete will still run the
                full cleanup.
              </p>
            )}
          </div>

          <DialogFooter>
            <Button
              variant="outline"
              onClick={() => {
                setDeleteTarget(null);
                setPreview(null);
              }}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={runDelete}
              disabled={loading}
            >
              {loading ? "Deleting…" : "Delete permanently"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
