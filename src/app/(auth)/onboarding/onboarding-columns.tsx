"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { StatusBadge } from "@/components/shared/status-badge";
import type { OnboardingListItem } from "@/lib/firestore/onboarding";

export const onboardingColumns: ColumnDef<OnboardingListItem>[] = [
  {
    accessorKey: "schoolName",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="School" />
    ),
  },
  {
    accessorKey: "contactPerson",
    header: "Contact",
    cell: ({ row }) => (
      <div>
        <p className="font-medium">
          {row.original.contactPerson || "\u2014"}
        </p>
        <p className="text-sm text-muted-foreground">
          {row.original.contactEmail}
        </p>
      </div>
    ),
  },
  {
    accessorKey: "status",
    header: "Status",
    cell: ({ row }) => <StatusBadge status={row.original.status} />,
  },
  {
    accessorKey: "currentStep",
    header: "Step",
    cell: ({ row }) => (
      <span className="capitalize">
        {row.original.currentStep.replace(/([A-Z])/g, " $1").trim()}
      </span>
    ),
  },
  {
    accessorKey: "estimatedStudentCount",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Est. Students" />
    ),
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
