"use client";

import { type ColumnDef } from "@tanstack/react-table";
import type { RecentActivity } from "@/lib/firestore/reading-logs";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";

const columns: ColumnDef<RecentActivity>[] = [
  {
    accessorKey: "studentId",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Student ID" />
    ),
    cell: ({ row }) => (
      <span className="font-mono text-sm">{row.getValue("studentId")}</span>
    ),
  },
  {
    accessorKey: "schoolId",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="School ID" />
    ),
    cell: ({ row }) => (
      <span className="font-mono text-sm">{row.getValue("schoolId")}</span>
    ),
  },
  {
    accessorKey: "minutesRead",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Minutes" />
    ),
  },
  {
    accessorKey: "bookTitles",
    header: "Books",
    cell: ({ row }) => {
      const titles = row.getValue("bookTitles") as string[];
      return titles.length > 0 ? titles.join(", ") : "—";
    },
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => <StatusBadge status={row.getValue("status")} />,
  },
  {
    accessorKey: "createdAt",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Date" />
    ),
    cell: ({ row }) => {
      const date = row.getValue("createdAt") as Date;
      return date.toLocaleDateString("en-AU", {
        day: "numeric",
        month: "short",
        hour: "2-digit",
        minute: "2-digit",
      });
    },
  },
];

interface RecentActivityTableProps {
  data: RecentActivity[];
}

export function RecentActivityTable({ data }: RecentActivityTableProps) {
  return <DataTable columns={columns} data={data} pageSize={10} />;
}
