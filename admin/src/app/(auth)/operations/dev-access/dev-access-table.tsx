"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import { DataTable } from "@/components/data-table/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { formatDate } from "@/lib/utils";
import type { DevAccessEmail } from "@/lib/firestore/dev-access";

interface Props {
  initialEmails: DevAccessEmail[];
}

export function DevAccessTable({ initialEmails }: Props) {
  const router = useRouter();
  const [emails] = useState<DevAccessEmail[]>(initialEmails);
  const [addOpen, setAddOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [note, setNote] = useState("");
  const [addLoading, setAddLoading] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<DevAccessEmail | null>(null);
  const [revokeLoading, setRevokeLoading] = useState(false);

  const resetAddForm = () => {
    setEmail("");
    setNote("");
  };

  const handleAdd = async () => {
    const trimmed = email.trim().toLowerCase();
    if (!trimmed) {
      toast.error("Enter an email");
      return;
    }
    setAddLoading(true);
    try {
      const res = await fetch("/api/dev-access", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: trimmed,
          note: note.trim() || undefined,
        }),
      });
      const json = (await res.json()) as { error?: string };
      if (!res.ok) throw new Error(json.error ?? "Failed to grant dev access");
      toast.success(`Granted dev access to ${trimmed}`);
      setAddOpen(false);
      resetAddForm();
      router.refresh();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to grant access");
    } finally {
      setAddLoading(false);
    }
  };

  const handleRevoke = async () => {
    if (!revokeTarget) return;
    setRevokeLoading(true);
    try {
      const res = await fetch(`/api/dev-access/${revokeTarget.id}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const json = (await res.json().catch(() => ({}))) as { error?: string };
        throw new Error(json.error ?? "Failed to revoke");
      }
      toast.success(`Revoked dev access for ${revokeTarget.email}`);
      setRevokeTarget(null);
      router.refresh();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed to revoke");
    } finally {
      setRevokeLoading(false);
    }
  };

  const columns: ColumnDef<DevAccessEmail, unknown>[] = useMemo(
    () => [
      {
        accessorKey: "email",
        header: "Email",
        cell: ({ row }) => (
          <span className="font-medium">{row.original.email}</span>
        ),
      },
      {
        accessorKey: "note",
        header: "Note",
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground">
            {row.original.note || "—"}
          </span>
        ),
      },
      {
        accessorKey: "addedByEmail",
        header: "Added by",
        cell: ({ row }) => (
          <span className="text-sm text-muted-foreground">
            {row.original.addedByEmail || row.original.addedBy}
          </span>
        ),
      },
      {
        accessorKey: "addedAt",
        header: "Added",
        cell: ({ row }) => formatDate(row.original.addedAt),
      },
      {
        id: "actions",
        header: "",
        cell: ({ row }) => (
          <Button
            variant="ghost"
            size="sm"
            className="text-destructive"
            onClick={(e) => {
              e.stopPropagation();
              setRevokeTarget(row.original);
            }}
          >
            Revoke
          </Button>
        ),
      },
    ],
    []
  );

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-end">
        <Button onClick={() => setAddOpen(true)}>
          <Plus className="mr-2 h-4 w-4" />
          Grant dev access
        </Button>
      </div>

      <DataTable
        columns={columns}
        data={emails}
        searchKey="email"
        searchPlaceholder="Search emails..."
      />

      <Dialog
        open={addOpen}
        onOpenChange={(open) => {
          if (!addLoading) {
            setAddOpen(open);
            if (!open) resetAddForm();
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Grant dev access</DialogTitle>
            <DialogDescription>
              This user will see DEV-only surfaces in the mobile app and school admin portal once they sign in.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label htmlFor="dev-access-email">Email</Label>
              <Input
                id="dev-access-email"
                type="email"
                placeholder="teammate@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="off"
                autoFocus
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="dev-access-note">Note (optional)</Label>
              <Input
                id="dev-access-note"
                placeholder="e.g. QA engineer"
                value={note}
                onChange={(e) => setNote(e.target.value)}
                maxLength={200}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="ghost"
              onClick={() => {
                setAddOpen(false);
                resetAddForm();
              }}
              disabled={addLoading}
            >
              Cancel
            </Button>
            <Button onClick={handleAdd} disabled={addLoading}>
              {addLoading ? "Granting…" : "Grant access"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={!!revokeTarget}
        onOpenChange={(open) => {
          if (!open && !revokeLoading) setRevokeTarget(null);
        }}
        title="Revoke dev access"
        description={
          revokeTarget
            ? `${revokeTarget.email} will no longer see DEV-only surfaces. They'll need to be granted access again to regain it.`
            : ""
        }
        confirmLabel="Revoke"
        variant="destructive"
        onConfirm={handleRevoke}
        loading={revokeLoading}
      />
    </div>
  );
}
