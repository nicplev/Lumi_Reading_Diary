"use client";

import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
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

type FeedbackStatusFilter = "all" | "new" | "reviewed" | "resolved";

export function FeedbackTable({
  data,
  initialStatus = "all",
  initialItemId,
}: {
  data: FeedbackListItem[];
  initialStatus?: string;
  initialItemId?: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [loading, setLoading] = useState(false);
  const [statusFilter, setStatusFilter] = useState<FeedbackStatusFilter>(
    initialStatus as FeedbackStatusFilter
  );
  const [selectedFeedback, setSelectedFeedback] = useState<FeedbackListItem | null>(
    data.find((item) => item.id === initialItemId) ?? null
  );

  const filteredData =
    statusFilter === "all"
      ? data
      : data.filter((item) => item.status === statusFilter);

  const replaceQuery = (updates: Record<string, string | null>) => {
    const params = new URLSearchParams(searchParams.toString());
    for (const [key, value] of Object.entries(updates)) {
      if (value) params.set(key, value);
      else params.delete(key);
    }
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };

  const changeStatusFilter = (status: FeedbackStatusFilter) => {
    setStatusFilter(status);
    setSelectedFeedback(null);
    replaceQuery({ status: status === "all" ? null : status, item: null });
  };

  const openFeedback = (item: FeedbackListItem) => {
    setSelectedFeedback(item);
    replaceQuery({ item: item.id });
  };

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
      setSelectedFeedback(null);
      replaceQuery({ item: null });
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
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <span className="text-sm font-medium">Status</span>
        <Select
          value={statusFilter}
          onValueChange={(value) =>
            value && changeStatusFilter(value as FeedbackStatusFilter)
          }
        >
          <SelectTrigger className="w-[180px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All feedback</SelectItem>
            <SelectItem value="new">New</SelectItem>
            <SelectItem value="reviewed">Reviewed</SelectItem>
            <SelectItem value="resolved">Resolved</SelectItem>
          </SelectContent>
        </Select>
        <span className="text-sm text-muted-foreground">
          {filteredData.length} item{filteredData.length === 1 ? "" : "s"}
        </span>
      </div>

      <DataTable
        columns={columns}
        data={filteredData}
        searchKey="description"
        searchPlaceholder="Search feedback..."
        onRowClick={openFeedback}
      />

      <Dialog
        open={selectedFeedback !== null}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedFeedback(null);
            replaceQuery({ item: null });
          }
        }}
      >
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Feedback detail</DialogTitle>
          </DialogHeader>
          {selectedFeedback && (
            <div className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <p className="text-sm text-muted-foreground">Category</p>
                  <p className="font-medium">
                    {categoryLabels[selectedFeedback.category] ?? selectedFeedback.category}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Status</p>
                  <StatusBadge status={selectedFeedback.status} />
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Submitted by</p>
                  <p className="font-medium capitalize">{selectedFeedback.userRole}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Date</p>
                  <p className="font-medium">{formatDate(selectedFeedback.createdAt)}</p>
                </div>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">Description</p>
                <p className="whitespace-pre-wrap text-sm">{selectedFeedback.description}</p>
              </div>
              <div>
                <p className="text-sm text-muted-foreground">User ID</p>
                <p className="font-mono text-xs">{selectedFeedback.userId}</p>
              </div>
              <div className="flex justify-end">
                <StatusActions
                  row={selectedFeedback}
                  onUpdate={handleStatusUpdate}
                  loading={loading}
                />
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
