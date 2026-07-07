"use client";

import { useState, type MouseEvent, type ReactNode } from "react";
import { toast } from "sonner";
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

interface BulkDeleteResult {
  requested: number;
  processed: number;
  truncated: boolean;
  deleted: number;
  failed: number;
}

type SoftAction = "disable" | "enable" | "resetPassword" | "resetMfa";

interface BulkTarget {
  parents: ParentListItem[];
  onDone?: () => void;
}

export interface ParentAccountActions {
  /** Inline ghost-button action cell for one parent row. */
  actionsCell: (parent: ParentListItem) => ReactNode;
  /** Open the bulk-delete confirm for a set of parents. */
  requestBulkDelete: (parents: ParentListItem[], onDone?: () => void) => void;
  /** Render once per table — all the confirm/preview/bulk dialogs. */
  dialogs: ReactNode;
}

const SOFT_COPY: Record<
  SoftAction,
  { title: string; confirmLabel: string; destructive: boolean }
> = {
  disable: { title: "Disable Parent", confirmLabel: "Disable", destructive: true },
  enable: { title: "Enable Parent", confirmLabel: "Enable", destructive: false },
  resetPassword: {
    title: "Reset Password",
    confirmLabel: "Generate link",
    destructive: false,
  },
  resetMfa: { title: "Reset MFA", confirmLabel: "Reset MFA", destructive: true },
};

function softDescription(action: SoftAction, name: string): string {
  switch (action) {
    case "disable":
      return `Block ${name} from signing in? Their account and data are kept and this can be undone.`;
    case "enable":
      return `Re-enable sign-in for ${name}?`;
    case "resetPassword":
      return `Generate a password reset link for ${name}? It will be copied to your clipboard.`;
    case "resetMfa":
      return `Clear ${name}'s enrolled phone (2-factor) so they can re-enrol on next login? Their account, email and linked children are kept.`;
  }
}

/**
 * All parent-account mutations (disable/enable/reset password/reset MFA/delete
 * + bulk delete), shared by the cross-school Parents page and each school's
 * Parents tab so the two stay identical. `onChanged` is called after any
 * successful mutation (callers pass `router.refresh()`).
 */
export function useParentAccountActions(opts: {
  onChanged: () => void;
}): ParentAccountActions {
  const { onChanged } = opts;

  const [softAction, setSoftAction] = useState<{
    parent: ParentListItem;
    action: SoftAction;
  } | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<ParentListItem | null>(null);
  const [preview, setPreview] = useState<ParentAccountPreview | null>(null);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [bulkTarget, setBulkTarget] = useState<BulkTarget | null>(null);
  const [loading, setLoading] = useState(false);

  const parentUrl = (p: ParentListItem) =>
    `/api/schools/${p.schoolId}/parents/${p.id}`;

  const runSoftAction = async () => {
    if (!softAction) return;
    const { parent, action } = softAction;
    setLoading(true);
    try {
      const res = await fetch(parentUrl(parent), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      });
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
      } else if (action === "resetMfa") {
        toast.success(`MFA reset for ${parent.fullName}`, {
          description: "Their phone is freed — they can re-enrol on next login.",
        });
      } else {
        toast.success(
          action === "disable"
            ? `${parent.fullName} disabled`
            : `${parent.fullName} re-enabled`
        );
      }
      setSoftAction(null);
      onChanged();
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
      const res = await fetch(parentUrl(parent));
      if (res.ok) setPreview((await res.json()) as ParentAccountPreview);
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
      const res = await fetch(parentUrl(deleteTarget), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "delete" }),
      });
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
      onChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Delete failed");
    } finally {
      setLoading(false);
    }
  };

  const runBulkDelete = async () => {
    if (!bulkTarget) return;
    const { parents, onDone } = bulkTarget;
    setLoading(true);
    try {
      const res = await fetch(`/api/parents/bulk-delete`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          items: parents.map((p) => ({ schoolId: p.schoolId, parentId: p.id })),
        }),
      });
      const data = (await res.json()) as BulkDeleteResult & { error?: string };
      if (!res.ok) throw new Error(data.error || "Bulk delete failed");

      const { deleted, failed, truncated, requested, processed } = data;
      const extra = truncated
        ? ` (capped at ${processed} of ${requested})`
        : "";
      if (failed === 0) {
        toast.success(
          `Deleted ${deleted} parent${deleted === 1 ? "" : "s"}${extra}`
        );
      } else if (deleted === 0) {
        toast.error(`Bulk delete failed for all ${failed} parents${extra}`);
      } else {
        toast.warning(`Deleted ${deleted}, ${failed} failed${extra}`);
      }
      setBulkTarget(null);
      onDone?.();
      onChanged();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Bulk delete failed");
    } finally {
      setLoading(false);
    }
  };

  const actionsCell = (parent: ParentListItem): ReactNode => {
    const stop =
      (fn: () => void) => (e: MouseEvent) => {
        e.stopPropagation();
        fn();
      };
    return (
      <div className="flex justify-end gap-1">
        <Button
          variant="ghost"
          size="sm"
          onClick={stop(() => setSoftAction({ parent, action: "resetPassword" }))}
        >
          Reset PW
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={stop(() => setSoftAction({ parent, action: "resetMfa" }))}
        >
          Reset MFA
        </Button>
        <Button
          variant="ghost"
          size="sm"
          onClick={stop(() =>
            setSoftAction({
              parent,
              action: parent.isActive ? "disable" : "enable",
            })
          )}
        >
          {parent.isActive ? "Disable" : "Enable"}
        </Button>
        <Button
          variant="ghost"
          size="sm"
          className="text-destructive"
          onClick={stop(() => openDelete(parent))}
        >
          Delete
        </Button>
      </div>
    );
  };

  const requestBulkDelete = (parents: ParentListItem[], onDone?: () => void) => {
    if (parents.length === 0) return;
    setBulkTarget({ parents, onDone });
  };

  const dialogs = (
    <>
      {/* Disable / Enable / Reset-password / Reset-MFA */}
      <ConfirmDialog
        open={!!softAction}
        onOpenChange={(open) => {
          if (!open) setSoftAction(null);
        }}
        title={softAction ? SOFT_COPY[softAction.action].title : ""}
        description={
          softAction
            ? softDescription(softAction.action, softAction.parent.fullName)
            : ""
        }
        confirmLabel={
          softAction ? SOFT_COPY[softAction.action].confirmLabel : "Confirm"
        }
        variant={
          softAction && SOFT_COPY[softAction.action].destructive
            ? "destructive"
            : "default"
        }
        onConfirm={runSoftAction}
        loading={loading}
      />

      {/* Single hard delete (frees email + phone for reuse) */}
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
                  {preview.phoneNumber ?? preview.mfaPhones[0] ?? "—"}
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
            <Button variant="destructive" onClick={runDelete} disabled={loading}>
              {loading ? "Deleting…" : "Delete permanently"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Bulk hard delete */}
      <Dialog
        open={!!bulkTarget}
        onOpenChange={(open) => {
          if (!open) setBulkTarget(null);
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              Delete {bulkTarget?.parents.length ?? 0} parent
              {bulkTarget?.parents.length === 1 ? "" : "s"}
            </DialogTitle>
            <DialogDescription>
              Permanently removes every account below from Firebase Auth and
              Firestore, freeing each email and phone for reuse. This cannot be
              undone.
            </DialogDescription>
          </DialogHeader>

          <div className="max-h-64 overflow-y-auto rounded-md border bg-muted/40 p-3 text-sm">
            <ul className="space-y-1">
              {bulkTarget?.parents.map((p) => (
                <li key={`${p.schoolId}:${p.id}`}>
                  <span className="font-medium text-foreground">
                    {p.fullName}
                  </span>{" "}
                  <span className="text-muted-foreground">
                    {p.email || "no email"}
                    {p.schoolName ? ` · ${p.schoolName}` : ""}
                  </span>
                </li>
              ))}
            </ul>
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setBulkTarget(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={runBulkDelete}
              disabled={loading}
            >
              {loading
                ? "Deleting…"
                : `Delete ${bulkTarget?.parents.length ?? 0} parent${
                    bulkTarget?.parents.length === 1 ? "" : "s"
                  }`}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );

  return { actionsCell, requestBulkDelete, dialogs };
}
