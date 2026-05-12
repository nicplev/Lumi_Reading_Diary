"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/utils";
import type { FeedbackListItem } from "@/lib/firestore/feedback";

const categoryLabels: Record<string, string> = {
  bug: "Bug Report",
  featureRequest: "Feature Request",
  general: "General",
};

function StatusActions({
  row,
  onUpdate,
  loading,
}: {
  row: FeedbackListItem;
  onUpdate: (id: string, status: string) => void;
  loading: boolean;
}) {
  if (row.status === "resolved") return null;

  return (
    <div className="flex items-center gap-1">
      {row.status === "new" && (
        <Button
          variant="ghost"
          size="sm"
          disabled={loading}
          onClick={(e) => {
            e.stopPropagation();
            onUpdate(row.id, "reviewed");
          }}
        >
          Mark Reviewed
        </Button>
      )}
      <Button
        variant="ghost"
        size="sm"
        className="text-green-700 hover:text-green-800"
        disabled={loading}
        onClick={(e) => {
          e.stopPropagation();
          onUpdate(row.id, "resolved");
        }}
      >
        Resolve
      </Button>
    </div>
  );
}

export function FeedbackTable({ data }: { data: FeedbackListItem[] }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  const handleStatusUpdate = async (id: string, status: string) => {
    setLoading(true);
    try {
      const res = await fetch(`/api/feedback/${id}/status`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.error || "Failed to update status");
      }
      toast.success(`Feedback marked as ${status}`);
      router.refresh();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Failed to update status"
      );
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<FeedbackListItem>[] = [
    {
      accessorKey: "category",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Category" />
      ),
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.category}
        />
      ),
      filterFn: (row, id, value) => row.getValue<string>(id) === value,
    },
    {
      accessorKey: "description",
      header: "Description",
      cell: ({ row }) => (
        <div className="max-w-[400px] truncate" title={row.original.description}>
          {row.original.description}
        </div>
      ),
    },
    {
      accessorKey: "userRole",
      header: "Role",
      cell: ({ row }) => (
        <StatusBadge status={row.original.userRole} />
      ),
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
        <StatusActions
          row={row.original}
          onUpdate={handleStatusUpdate}
          loading={loading}
        />
      ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={data}
      searchKey="description"
      searchPlaceholder="Search feedback..."
    />
  );
}
