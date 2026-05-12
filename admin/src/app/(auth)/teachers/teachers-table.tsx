"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";

interface TeachersTableProps {
  teachers: SchoolUserListItem[];
}

const columns: ColumnDef<SchoolUserListItem, unknown>[] = [
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
    accessorKey: "role",
    header: "Role",
    cell: ({ row }) => <StatusBadge status={row.original.role} />,
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

export function TeachersTable({ teachers }: TeachersTableProps) {
  const router = useRouter();

  return (
    <DataTable
      columns={columns}
      data={teachers}
      searchKey="fullName"
      searchPlaceholder="Search teachers..."
      onRowClick={(row) =>
        router.push(`/schools/${row.schoolId}?tab=users`)
      }
    />
  );
}
