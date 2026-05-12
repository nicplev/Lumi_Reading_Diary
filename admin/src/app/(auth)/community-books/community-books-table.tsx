"use client";

import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { DataTableColumnHeader } from "@/components/data-table/data-table-column-header";
import { formatDate } from "@/lib/utils";
import type { CommunityBookListItem } from "@/lib/firestore/community-books";

const columns: ColumnDef<CommunityBookListItem>[] = [
  {
    accessorKey: "title",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Title" />
    ),
    cell: ({ row }) => (
      <div>
        <div className="font-medium">{row.original.title || "Untitled"}</div>
        <div className="text-xs text-muted-foreground">{row.original.isbn}</div>
      </div>
    ),
  },
  {
    accessorKey: "author",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Author" />
    ),
    cell: ({ row }) => row.original.author || "—",
  },
  {
    accessorKey: "readingLevel",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Level" />
    ),
    cell: ({ row }) => row.original.readingLevel || "—",
  },
  {
    accessorKey: "source",
    header: "Source",
    cell: ({ row }) => (
      <code className="rounded bg-muted px-2 py-1 text-xs">
        {row.original.source || "—"}
      </code>
    ),
  },
  {
    accessorKey: "contributedByName",
    header: "Contributed By",
    cell: ({ row }) => row.original.contributedByName || "—",
  },
  {
    accessorKey: "createdAt",
    header: ({ column }) => (
      <DataTableColumnHeader column={column} title="Added" />
    ),
    cell: ({ row }) => formatDate(row.original.createdAt),
  },
];

export function CommunityBooksTable({
  data,
}: {
  data: CommunityBookListItem[];
}) {
  return (
    <DataTable
      columns={columns}
      data={data}
      searchKey="title"
      searchPlaceholder="Search by title..."
    />
  );
}
