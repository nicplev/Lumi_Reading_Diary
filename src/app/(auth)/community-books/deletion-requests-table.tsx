"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { Check, X } from "lucide-react";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { formatDate } from "@/lib/utils";
import type { DeletionRequestListItem } from "@/lib/firestore/community-books";

interface ResolveState {
  id: string;
  isbn: string;
  bookTitle: string;
  action: "approved" | "rejected";
}

function ActionsCell({
  row,
  onResolve,
}: {
  row: DeletionRequestListItem;
  onResolve: (state: ResolveState) => void;
}) {
  return (
    <div className="flex items-center gap-1">
      <Button
        variant="ghost"
        size="sm"
        className="text-green-700 hover:text-green-800"
        onClick={(e) => {
          e.stopPropagation();
          onResolve({
            id: row.id,
            isbn: row.isbn,
            bookTitle: row.bookTitle,
            action: "approved",
          });
        }}
      >
        <Check className="mr-1 h-3 w-3" />
        Approve
      </Button>
      <Button
        variant="ghost"
        size="sm"
        className="text-destructive"
        onClick={(e) => {
          e.stopPropagation();
          onResolve({
            id: row.id,
            isbn: row.isbn,
            bookTitle: row.bookTitle,
            action: "rejected",
          });
        }}
      >
        <X className="mr-1 h-3 w-3" />
        Reject
      </Button>
    </div>
  );
}

export function DeletionRequestsTable({
  data,
}: {
  data: DeletionRequestListItem[];
}) {
  const router = useRouter();
  const [resolveState, setResolveState] = useState<ResolveState | null>(null);
  const [loading, setLoading] = useState(false);

  const handleResolve = async () => {
    if (!resolveState) return;
    setLoading(true);
    try {
      const res = await fetch(
        `/api/community-books/deletion-requests/${resolveState.id}/resolve`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            isbn: resolveState.isbn,
            action: resolveState.action,
          }),
        }
      );
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error || "Failed to resolve request");
      }
      toast.success(
        resolveState.action === "approved"
          ? "Book deleted successfully"
          : "Request rejected"
      );
      setResolveState(null);
      router.refresh();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to resolve request"
      );
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<DeletionRequestListItem>[] = [
    {
      accessorKey: "bookTitle",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Book" />
      ),
      cell: ({ row }) => (
        <div>
          <div className="font-medium">{row.original.bookTitle || "Unknown"}</div>
          <div className="text-xs text-muted-foreground">
            {row.original.isbn}
          </div>
        </div>
      ),
    },
    {
      accessorKey: "bookAuthor",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Author" />
      ),
    },
    {
      accessorKey: "reason",
      header: "Reason",
      cell: ({ row }) => (
        <div className="max-w-[300px] truncate" title={row.original.reason}>
          {row.original.reason}
        </div>
      ),
    },
    {
      accessorKey: "requestedByName",
      header: "Requested By",
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: "createdAt",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Date" />
      ),
      cell: ({ row }) => formatDate(row.original.createdAt),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <ActionsCell row={row.original} onResolve={setResolveState} />
      ),
    },
  ];

  const isApprove = resolveState?.action === "approved";

  return (
    <>
      <DataTable
        columns={columns}
        data={data}
        searchKey="bookTitle"
        searchPlaceholder="Search by book title..."
      />
      <ConfirmDialog
        open={!!resolveState}
        onOpenChange={(open) => {
          if (!open) setResolveState(null);
        }}
        title={isApprove ? "Approve Deletion" : "Reject Request"}
        description={
          isApprove
            ? `This will permanently delete "${resolveState?.bookTitle}" from the community library and all school libraries.`
            : `Reject the deletion request for "${resolveState?.bookTitle}"? The book will remain in the community library.`
        }
        confirmLabel={isApprove ? "Delete Book" : "Reject"}
        variant={isApprove ? "destructive" : "default"}
        onConfirm={handleResolve}
        loading={loading}
      />
    </>
  );
}
