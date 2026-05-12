"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";

interface ClassesTableProps {
  classes: ClassListItem[];
  users: SchoolUserListItem[];
}

export function ClassesTable({ classes, users }: ClassesTableProps) {
  const router = useRouter();
  const teacherMap = new Map(users.map((u) => [u.id, u.fullName]));

  const columns: ColumnDef<ClassListItem, unknown>[] = [
    {
      accessorKey: "name",
      header: ({ column }) => (
        <DataTableColumnHeader column={column} title="Name" />
      ),
    },
    {
      accessorKey: "yearLevel",
      header: "Year",
      cell: ({ row }) => row.original.yearLevel ?? "\u2014",
    },
    {
      accessorKey: "schoolName",
      header: "School",
      cell: ({ row }) => row.original.schoolName ?? "\u2014",
    },
    {
      accessorKey: "teacherId",
      header: "Teacher",
      cell: ({ row }) =>
        teacherMap.get(row.original.teacherId) ?? "\u2014",
    },
    {
      accessorKey: "studentCount",
      header: "Students",
      cell: ({ row }) => row.original.studentCount,
    },
    {
      accessorKey: "isActive",
      header: "Status",
      cell: ({ row }) => (
        <StatusBadge
          status={row.original.isActive ? "active" : "disabled"}
        />
      ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={classes}
      searchKey="name"
      searchPlaceholder="Search classes..."
      onRowClick={(row) =>
        router.push(`/schools/${row.schoolId}?tab=classes`)
      }
    />
  );
}
