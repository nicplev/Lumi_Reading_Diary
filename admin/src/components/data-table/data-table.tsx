"use client";

import { useState, type ReactNode } from "react";
import {
  type ColumnDef,
  type SortingState,
  type ColumnFiltersState,
  type RowSelectionState,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  useReactTable,
} from "@tanstack/react-table";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { DataTablePagination } from "./data-table-pagination";

interface DataTableProps<TData, TValue> {
  columns: ColumnDef<TData, TValue>[];
  data: TData[];
  searchKey?: string;
  searchPlaceholder?: string;
  pageSize?: number;
  onRowClick?: (row: TData) => void;
  /** Opt-in multi-row selection with a leading checkbox column. */
  enableRowSelection?: boolean;
  /** Stable row id (recommended with selection so it survives sort/paging). */
  getRowId?: (row: TData) => string;
  /** Rendered in a bar above the table while rows are selected. */
  renderBulkActions?: (selected: TData[], clear: () => void) => ReactNode;
}

export function DataTable<TData, TValue>({
  columns,
  data,
  searchKey,
  searchPlaceholder,
  pageSize = 10,
  onRowClick,
  enableRowSelection = false,
  getRowId,
  renderBulkActions,
}: DataTableProps<TData, TValue>) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [columnFilters, setColumnFilters] = useState<ColumnFiltersState>([]);
  const [rowSelection, setRowSelection] = useState<RowSelectionState>({});

  // A checkbox column, prepended only when selection is enabled. Both the
  // header and cell checkboxes stopPropagation so clicking them never triggers
  // the row-level onClick (used elsewhere for navigation).
  const selectionColumn: ColumnDef<TData, TValue> = {
    id: "__select__",
    enableSorting: false,
    header: ({ table }) => (
      <div
        className="flex items-center"
        onClick={(e) => e.stopPropagation()}
      >
        <Checkbox
          checked={table.getIsAllPageRowsSelected()}
          indeterminate={
            table.getIsSomePageRowsSelected() &&
            !table.getIsAllPageRowsSelected()
          }
          onCheckedChange={(v) => table.toggleAllPageRowsSelected(!!v)}
          aria-label="Select all rows on this page"
        />
      </div>
    ),
    cell: ({ row }) => (
      <div className="flex items-center" onClick={(e) => e.stopPropagation()}>
        <Checkbox
          checked={row.getIsSelected()}
          onCheckedChange={(v) => row.toggleSelected(!!v)}
          aria-label="Select row"
        />
      </div>
    ),
  };

  const resolvedColumns = enableRowSelection
    ? [selectionColumn, ...columns]
    : columns;

  const table = useReactTable({
    data,
    columns: resolvedColumns,
    getCoreRowModel: getCoreRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    onSortingChange: setSorting,
    onColumnFiltersChange: setColumnFilters,
    enableRowSelection,
    onRowSelectionChange: setRowSelection,
    getRowId,
    state: { sorting, columnFilters, rowSelection },
    initialState: { pagination: { pageSize } },
  });

  const selectedRows = table.getSelectedRowModel().rows.map((r) => r.original);

  return (
    <div className="space-y-4">
      {searchKey && (
        <Input
          placeholder={searchPlaceholder || `Search...`}
          value={
            (table.getColumn(searchKey)?.getFilterValue() as string) ?? ""
          }
          onChange={(e) =>
            table.getColumn(searchKey)?.setFilterValue(e.target.value)
          }
          className="max-w-sm"
        />
      )}
      {enableRowSelection && renderBulkActions && selectedRows.length > 0 && (
        <div className="flex items-center gap-3 rounded-md border bg-muted/40 px-3 py-2">
          <span className="text-sm text-muted-foreground">
            {selectedRows.length} selected
          </span>
          {renderBulkActions(selectedRows, () => setRowSelection({}))}
        </div>
      )}
      <div className="rounded-md border">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((headerGroup) => (
              <TableRow key={headerGroup.id}>
                {headerGroup.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(
                          header.column.columnDef.header,
                          header.getContext()
                        )}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {table.getRowModel().rows?.length ? (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  data-state={row.getIsSelected() ? "selected" : undefined}
                  className={onRowClick ? "cursor-pointer hover:bg-muted/50" : undefined}
                  onClick={() => onRowClick?.(row.original)}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(
                        cell.column.columnDef.cell,
                        cell.getContext()
                      )}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={resolvedColumns.length}
                  className="h-24 text-center"
                >
                  No results.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>
      <DataTablePagination table={table} />
    </div>
  );
}
