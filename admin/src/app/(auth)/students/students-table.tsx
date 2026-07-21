"use client";

import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { StudentListItem } from "@/lib/firestore/students";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

interface StudentsTableProps {
  students: StudentListItem[];
  initialStatus: "all" | "active";
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

export function StudentsTable({ students, initialStatus }: StudentsTableProps) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [status, setStatus] = useState(initialStatus);
  const filtered =
    status === "active" ? students.filter((student) => student.isActive) : students;

  const changeStatus = (next: "all" | "active") => {
    setStatus(next);
    const params = new URLSearchParams(searchParams.toString());
    if (next === "active") params.set("status", "active");
    else params.delete("status");
    const query = params.toString();
    router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
  };

  return (
    <div className="space-y-4">
      <Select
        value={status}
        onValueChange={(value) =>
          value && changeStatus(value as "all" | "active")
        }
      >
        <SelectTrigger className="w-[180px]">
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="all">All students</SelectItem>
          <SelectItem value="active">Active students</SelectItem>
        </SelectContent>
      </Select>
      <DataTable
        columns={columns}
        data={filtered}
        searchKey="firstName"
        searchPlaceholder="Search students..."
        onRowClick={(row) =>
          router.push(`/schools/${row.schoolId}/students/${row.id}`)
        }
      />
    </div>
  );
}
