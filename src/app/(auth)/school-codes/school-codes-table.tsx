"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { Copy, Ban } from "lucide-react";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import type { SchoolCodeListItem } from "@/lib/firestore/school-codes";

function CopyButton({ code }: { code: string }) {
  const [copied, setCopied] = useState(false);

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={(e) => {
        e.stopPropagation();
        navigator.clipboard.writeText(code);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      }}
    >
      <Copy className="mr-1 h-3 w-3" />
      {copied ? "Copied" : code}
    </Button>
  );
}

function RevokeButton({ id, code }: { id: string; code: string }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);

  const handleRevoke = async () => {
    setLoading(true);
    try {
      await fetch(`/api/school-codes/${id}`, { method: "DELETE" });
      router.refresh();
    } finally {
      setLoading(false);
      setOpen(false);
    }
  };

  return (
    <>
      <Button
        variant="ghost"
        size="sm"
        onClick={(e) => {
          e.stopPropagation();
          setOpen(true);
        }}
      >
        <Ban className="mr-1 h-3 w-3" />
        Revoke
      </Button>
      <ConfirmDialog
        open={open}
        onOpenChange={setOpen}
        title="Revoke School Code"
        description={`Are you sure you want to revoke code "${code}"? This cannot be undone.`}
        confirmLabel="Revoke"
        variant="destructive"
        onConfirm={handleRevoke}
        loading={loading}
      />
    </>
  );
}

const columns: ColumnDef<SchoolCodeListItem>[] = [
  {
    accessorKey: "code",
    header: "Code",
    cell: ({ row }) => <CopyButton code={row.original.code} />,
  },
  {
    accessorKey: "schoolName",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="School" />
    ),
  },
  {
    accessorKey: "isActive",
    header: "Status",
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? "active" : "revoked"} />
    ),
  },
  {
    accessorKey: "usageCount",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Usage" />
    ),
    cell: ({ row }) => {
      const { usageCount, maxUsages } = row.original;
      return maxUsages ? `${usageCount}/${maxUsages}` : String(usageCount);
    },
  },
  {
    accessorKey: "expiresAt",
    header: "Expires",
    cell: ({ row }) => {
      const date = row.original.expiresAt;
      return date ? new Date(date).toLocaleDateString() : "Never";
    },
  },
  {
    accessorKey: "createdAt",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Created" />
    ),
    cell: ({ row }) => {
      const date = row.original.createdAt;
      return date ? new Date(date).toLocaleDateString() : "\u2014";
    },
  },
  {
    id: "actions",
    cell: ({ row }) => {
      if (!row.original.isActive) return null;
      return <RevokeButton id={row.original.id} code={row.original.code} />;
    },
  },
];

export function SchoolCodesTable({ data }: { data: SchoolCodeListItem[] }) {
  return (
    <DataTable
      columns={columns}
      data={data}
      searchKey="schoolName"
      searchPlaceholder="Search by school..."
    />
  );
}
