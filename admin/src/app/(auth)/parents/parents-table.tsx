"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { ParentListItem } from "@/lib/firestore/parents";

interface ParentsTableProps {
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
    header: "Children",
    cell: ({ row }) => row.original.linkedChildrenCount,
  },
  {
    accessorKey: "schoolName",
    header: "School",
    cell: ({ row }) => row.original.schoolName ?? "\u2014",
  },
  {
    accessorKey: "isActive",
    header: "Status",
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? "active" : "disabled"} />
    ),
  },
];

export function ParentsTable({ parents }: ParentsTableProps) {
  const router = useRouter();

  return (
    <DataTable
      columns={columns}
      data={parents}
      searchKey="fullName"
      searchPlaceholder="Search parents..."
      onRowClick={(row) =>
        router.push(`/schools/${row.schoolId}?tab=parents`)
      }
    />
  );
}
