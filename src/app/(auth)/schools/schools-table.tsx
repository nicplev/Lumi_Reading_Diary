"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { SchoolListItem } from "@/lib/firestore/schools";

const columns: ColumnDef<SchoolListItem>[] = [
  {
    accessorKey: "name",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Name" />
    ),
  },
  {
    accessorKey: "isActive",
    header: "Status",
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? "active" : "suspended"} />
    ),
  },
  {
    accessorKey: "studentCount",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Students" />
    ),
  },
  {
    accessorKey: "teacherCount",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Teachers" />
    ),
  },
  {
    accessorKey: "subscriptionPlan",
    header: "Subscription",
    cell: ({ row }) => row.original.subscriptionPlan ?? "\u2014",
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
];

export function SchoolsTable({ data }: { data: SchoolListItem[] }) {
  const router = useRouter();

  return (
    <DataTable
      columns={columns}
      data={data}
      searchKey="name"
      searchPlaceholder="Search schools..."
      onRowClick={(school) => router.push(`/schools/${school.id}`)}
    />
  );
}
