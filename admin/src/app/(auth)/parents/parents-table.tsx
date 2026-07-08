"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import type { ParentListItem } from "@/lib/firestore/parents";
import { useParentAccountActions } from "./use-parent-account-actions";

interface ParentsTableProps {
  parents: ParentListItem[];
}

// Heuristic for internal / throwaway accounts, so bulk cleanup can target them
// without touching real parents.
function isTestAccount(email?: string): boolean {
  if (!email) return false;
  const e = email.toLowerCase();
  return (
    e.endsWith("@lumi-reading.com") ||
    e.startsWith("support+") ||
    e.startsWith("review.")
  );
}

export function ParentsTable({ parents }: ParentsTableProps) {
  const router = useRouter();
  const [testOnly, setTestOnly] = useState(false);

  const { actionsCell, requestBulkDelete, dialogs } = useParentAccountActions({
    onChanged: () => router.refresh(),
  });

  const data = useMemo(
    () => (testOnly ? parents.filter((p) => isTestAccount(p.email)) : parents),
    [parents, testOnly]
  );

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
      cell: ({ row }) => row.original.schoolName ?? "—",
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
      <label className="flex w-fit items-center gap-2 text-sm text-muted-foreground">
        <Checkbox
          checked={testOnly}
          onCheckedChange={(v) => setTestOnly(!!v)}
        />
        Test accounts only
      </label>

      <DataTable
        columns={columns}
        data={data}
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
        onRowClick={(row) =>
          router.push(`/schools/${row.schoolId}?tab=parents`)
        }
      />

      {dialogs}
    </div>
  );
}
