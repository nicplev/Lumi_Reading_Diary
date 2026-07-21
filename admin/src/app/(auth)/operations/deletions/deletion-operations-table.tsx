"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import type { ColumnDef } from "@tanstack/react-table";
import { toast } from "sonner";
import { DataTable } from "@/components/data-table/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type {
  DeletionOperation,
  DeletionOperationStatus,
} from "@/lib/firestore/deletion-operations";
import { formatDateTime } from "@/lib/utils";

type StatusFilter = DeletionOperationStatus | "all";

const KIND_LABELS = {
  "staff-account": "Staff account",
  account: "Account",
  student: "Student",
} as const;

export function DeletionOperationsTable({
  operations,
  initialStatus,
}: {
  operations: DeletionOperation[];
  initialStatus: StatusFilter;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [status, setStatus] = useState<StatusFilter>(initialStatus);
  const [pendingTarget, setPendingTarget] = useState<{
    operation: DeletionOperation;
    action: "cancel" | "retry";
  } | null>(null);
  const [loading, setLoading] = useState(false);
  const filtered = useMemo(
    () => operations.filter((item) => status === "all" || item.status === status),
    [operations, status]
  );

  const changeStatus = (next: StatusFilter) => {
    setStatus(next);
    const params = new URLSearchParams(searchParams.toString());
    params.set("status", next);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const runAction = async () => {
    if (!pendingTarget) return;
    const { operation, action } = pendingTarget;
    if (action === "cancel" && !operation.userId) return;
    setLoading(true);
    try {
      const response = await fetch("/api/deletion-operations/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(
          action === "cancel"
            ? { userId: operation.userId, action }
            : { jobId: operation.id, action }
        ),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Cancellation failed");
      toast.success(
        action === "cancel"
          ? "Scheduled staff-account deletion cancelled"
          : "Deletion job queued for another attempt"
      );
      setPendingTarget(null);
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Cancellation failed");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<DeletionOperation>[] = [
    {
      accessorKey: "schoolName",
      header: "School",
      cell: ({ row }) =>
        row.original.schoolId ? (
          <Link
            href={`/schools/${encodeURIComponent(row.original.schoolId)}`}
            className="font-medium text-primary hover:underline"
          >
            {row.original.schoolName || "Unknown school"}
          </Link>
        ) : (
          "Platform account"
        ),
    },
    { accessorKey: "subjectName", header: "Subject" },
    {
      accessorKey: "kind",
      header: "Type",
      cell: ({ row }) => KIND_LABELS[row.original.kind],
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: "scheduledAt",
      header: "Scheduled / next attempt",
      cell: ({ row }) =>
        row.original.scheduledAt ? formatDateTime(row.original.scheduledAt) : "—",
    },
    {
      id: "attempt",
      header: "Attempts",
      cell: ({ row }) =>
        row.original.attemptCount > 0 ? row.original.attemptCount : "—",
    },
    {
      accessorKey: "errorCode",
      header: "Last error",
      cell: ({ row }) => row.original.errorCode || "—",
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        row.original.canCancel ? (
          <Button
            variant="outline"
            size="sm"
            onClick={() =>
              setPendingTarget({ operation: row.original, action: "cancel" })
            }
          >
            Cancel deletion
          </Button>
        ) : row.original.canRetry ? (
          <Button
            variant="outline"
            size="sm"
            onClick={() =>
              setPendingTarget({ operation: row.original, action: "retry" })
            }
          >
            Retry deletion
          </Button>
        ) : row.original.status === "retrying" ? (
          <span className="text-xs text-muted-foreground">Automatic retry scheduled</span>
        ) : null,
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <Select
          value={status}
          onValueChange={(value) => value && changeStatus(value as StatusFilter)}
        >
          <SelectTrigger className="w-[220px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All active deletions</SelectItem>
            <SelectItem value="cooling-off">Cooling-off period</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
            <SelectItem value="processing">Processing</SelectItem>
            <SelectItem value="retrying">Retrying automatically</SelectItem>
            <SelectItem value="manual-review">Manual review required</SelectItem>
          </SelectContent>
        </Select>
        <span className="text-sm text-muted-foreground">
          {filtered.length} operation{filtered.length === 1 ? "" : "s"}
        </span>
      </div>
      <DataTable
        columns={columns}
        data={filtered}
        searchKey="subjectName"
        searchPlaceholder="Search by subject..."
      />
      <ConfirmDialog
        open={pendingTarget !== null}
        onOpenChange={(open) => !open && !loading && setPendingTarget(null)}
        title={
          pendingTarget?.action === "retry"
            ? "Retry deletion job?"
            : "Cancel scheduled deletion?"
        }
        description={
          pendingTarget?.action === "retry"
            ? "The resumable deletion worker will make another attempt. Review the audit trail and job status after it runs."
            : "This restores the staff account's deletion state before the cooling-off period expires."
        }
        confirmLabel={
          pendingTarget?.action === "retry" ? "Queue retry" : "Cancel deletion"
        }
        onConfirm={runAction}
        loading={loading}
      />
    </div>
  );
}
