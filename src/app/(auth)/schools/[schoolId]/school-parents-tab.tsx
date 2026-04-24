"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import type { ParentListItem } from "@/lib/firestore/parents";

interface SchoolParentsTabProps {
  parents: ParentListItem[];
}

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
    header: "Linked Children",
    cell: ({ row }) => row.original.linkedChildrenCount,
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
      <StatusBadge status={row.original.isActive ? "active" : "disabled"} />
    ),
  },
];

export function SchoolParentsTab({ parents }: SchoolParentsTabProps) {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Parents</h3>
        <p className="text-sm text-muted-foreground">
          Parents self-register via link codes
        </p>
      </div>
      <DataTable
        columns={columns}
        data={parents}
        searchKey="fullName"
        searchPlaceholder="Search parents..."
      />
    </div>
  );
}
