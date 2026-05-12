"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import type { GlobalReadingLogItem } from "@/lib/firestore/reading-logs";

interface Props {
  logs: GlobalReadingLogItem[];
}

const columns: ColumnDef<GlobalReadingLogItem, unknown>[] = [
  {
    accessorKey: "schoolName",
    header: "School",
    cell: ({ row }) => row.original.schoolName ?? "\u2014",
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
    accessorKey: "date",
    header: "Date",
    cell: ({ row }) => formatDate(row.original.date),
  },
  {
    accessorKey: "minutesRead",
    header: "Minutes",
    cell: ({ row }) => `${row.original.minutesRead} min`,
  },
  {
    accessorKey: "bookTitles",
    header: "Books",
    cell: ({ row }) => {
      const t = row.original.bookTitles;
      if (!t.length) return "\u2014";
      const text = t.join(", ");
      return text.length > 30 ? text.slice(0, 30) + "..." : text;
    },
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
];

export function GlobalReadingLogsTable({ logs }: Props) {
  return (
    <DataTable
      columns={columns}
      data={logs}
      searchKey="schoolName"
      searchPlaceholder="Search by school..."
    />
  );
}
