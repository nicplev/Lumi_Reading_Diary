"use client";

import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/utils";
import type { ParentListItem } from "@/lib/firestore/parents";
import { useParentAccountActions } from "../../parents/use-parent-account-actions";

interface SchoolParentsTabProps {
  schoolId: string;
  parents: ParentListItem[];
}

export function SchoolParentsTab({ parents }: SchoolParentsTabProps) {
  const router = useRouter();
  const { actionsCell, requestBulkDelete, dialogs } = useParentAccountActions({
    onChanged: () => router.refresh(),
  });

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
    {
      id: "actions",
      header: "",
      cell: ({ row }) => actionsCell(row.original),
    },
  ];

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
        enableRowSelection
        getRowId={(p) => `${p.schoolId}:${p.id}`}
        renderBulkActions={(selected, clear) => (
          <Button
            variant="destructive"
            size="sm"
            onClick={() => requestBulkDelete(selected, clear)}
          >
            Delete {selected.length}
          </Button>
        )}
      />
      {dialogs}
    </div>
  );
}
