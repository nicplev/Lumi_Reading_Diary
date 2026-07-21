"use client";

import { useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import type { SchoolListItem } from "@/lib/firestore/schools";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

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
    cell: ({ row }) => formatDate(row.original.createdAt),
  },
];

export function SchoolsTable({
  data,
  initialStatus,
}: {
  data: SchoolListItem[];
  initialStatus: "all" | "active";
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [status, setStatus] = useState(initialStatus);
  const filtered = status === "active" ? data.filter((school) => school.isActive) : data;

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
          <SelectItem value="all">All schools</SelectItem>
          <SelectItem value="active">Active schools</SelectItem>
        </SelectContent>
      </Select>
      <DataTable
        columns={columns}
        data={filtered}
        searchKey="name"
        searchPlaceholder="Search schools..."
        onRowClick={(school) => router.push(`/schools/${school.id}`)}
      />
    </div>
  );
}
