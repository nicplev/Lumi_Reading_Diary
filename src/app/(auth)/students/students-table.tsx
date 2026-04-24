"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { StudentListItem } from "@/lib/firestore/students";

interface StudentsTableProps {
  students: StudentListItem[];
}

const columns: ColumnDef<StudentListItem, unknown>[] = [
  {
    accessorKey: "firstName",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Name" />
    ),
    cell: ({ row }) =>
      `${row.original.firstName} ${row.original.lastName}`,
  },
  {
    accessorKey: "schoolName",
    header: "School",
    cell: ({ row }) => row.original.schoolName ?? "\u2014",
  },
  {
    accessorKey: "currentReadingLevel",
    header: "Level",
    cell: ({ row }) => row.original.currentReadingLevel ?? "\u2014",
  },
  {
    accessorKey: "isActive",
    header: "Status",
    cell: ({ row }) => (
      <StatusBadge status={row.original.isActive ? "active" : "disabled"} />
    ),
  },
];

export function StudentsTable({ students }: StudentsTableProps) {
  const router = useRouter();

  return (
    <DataTable
      columns={columns}
      data={students}
      searchKey="firstName"
      searchPlaceholder="Search students..."
      onRowClick={(row) =>
        router.push(`/schools/${row.schoolId}/students/${row.id}`)
      }
    />
  );
}
