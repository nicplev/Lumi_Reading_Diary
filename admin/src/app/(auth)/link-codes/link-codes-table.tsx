"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { DataTable } from "@/components/data-table/data-table";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { formatDate } from "@/lib/utils";
import type { LinkCodeListItem } from "@/lib/firestore/link-codes";

interface Props {
  codes: LinkCodeListItem[];
}

export function LinkCodesTable({ codes }: Props) {
  const router = useRouter();
  const [filterStatus, setFilterStatus] = useState("all");
  const [revokeId, setRevokeId] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const filtered =
    filterStatus === "all"
      ? codes
      : codes.filter((c) => c.status === filterStatus);

  const handleRevoke = async () => {
    if (!revokeId) return;
    setLoading(true);
    try {
      const res = await fetch(`/api/link-codes/${revokeId}`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error("Failed to revoke");
      toast.success("Link code revoked");
      setRevokeId(null);
      router.refresh();
    } catch {
      toast.error("Failed to revoke link code");
    } finally {
      setLoading(false);
    }
  };

  const columns: ColumnDef<LinkCodeListItem, unknown>[] = [
    {
      accessorKey: "code",
      header: "Code",
      cell: ({ row }) => (
        <code className="rounded bg-muted px-2 py-1 font-mono text-sm">
          {row.original.code}
        </code>
      ),
    },
    {
      accessorKey: "studentId",
      header: "Student ID",
      cell: ({ row }) => (
        <span className="font-mono text-xs">
          {row.original.studentId.slice(0, 12)}...
        </span>
      ),
    },
    {
      accessorKey: "schoolId",
      header: "School ID",
      cell: ({ row }) => (
        <span className="font-mono text-xs">
          {row.original.schoolId.slice(0, 12)}...
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: "expiresAt",
      header: "Expires",
      cell: ({ row }) => formatDate(row.original.expiresAt),
    },
    {
      accessorKey: "createdAt",
      header: "Created",
      cell: ({ row }) => formatDate(row.original.createdAt),
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) =>
        row.original.status === "active" ? (
          <Button
            variant="ghost"
            size="sm"
            className="text-destructive"
            onClick={(e) => {
              e.stopPropagation();
              setRevokeId(row.original.id);
            }}
          >
            Revoke
          </Button>
        ) : null,
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <Select
          value={filterStatus}
          onValueChange={(v) => v && setFilterStatus(v)}
        >
          <SelectTrigger className="w-[160px]">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            <SelectItem value="active">Active</SelectItem>
            <SelectItem value="used">Used</SelectItem>
            <SelectItem value="expired">Expired</SelectItem>
            <SelectItem value="revoked">Revoked</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        searchKey="code"
        searchPlaceholder="Search by code..."
      />

      <ConfirmDialog
        open={!!revokeId}
        onOpenChange={(open) => {
          if (!open) setRevokeId(null);
        }}
        title="Revoke Link Code"
        description="This will invalidate the code. Parents who haven't used it yet won't be able to link."
        confirmLabel="Revoke"
        variant="destructive"
        onConfirm={handleRevoke}
        loading={loading}
      />
    </div>
  );
}
