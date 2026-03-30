'use client';

import { useState, useMemo } from 'react';
import {
  useReactTable,
  getCoreRowModel,
  getSortedRowModel,
  getPaginationRowModel,
  flexRender,
  type SortingState,
  type ColumnDef,
} from '@tanstack/react-table';
import { Skeleton } from './skeleton';
import { Button } from './button';

export interface DataTableColumn<T> {
  id: string;
  header: string;
  accessorFn: (row: T) => unknown;
  cell?: (value: unknown, row: T) => React.ReactNode;
  sortable?: boolean;
  className?: string;
}

interface DataTableProps<T> {
  columns: DataTableColumn<T>[];
  data: T[];
  searchValue?: string;
  onSearchChange?: (value: string) => void;
  pageSize?: number;
  emptyState?: React.ReactNode;
  onRowClick?: (row: T) => void;
  loading?: boolean;
}

export function DataTable<T>({
  columns,
  data,
  pageSize = 20,
  emptyState,
  onRowClick,
  loading,
}: DataTableProps<T>) {
  const [sorting, setSorting] = useState<SortingState>([]);

  const tanstackColumns: ColumnDef<T>[] = useMemo(
    () =>
      columns.map((col) => ({
        id: col.id,
        header: col.header,
        accessorFn: col.accessorFn,
        cell: col.cell
          ? (info: { getValue: () => unknown; row: { original: T } }) =>
              col.cell!(info.getValue(), info.row.original)
          : (info: { getValue: () => unknown }) => {
              const val = info.getValue();
              return val == null ? '' : String(val);
            },
        enableSorting: col.sortable ?? false,
        meta: { className: col.className },
      })),
    [columns]
  );

  const table = useReactTable({
    data,
    columns: tanstackColumns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize } },
  });

  if (loading) {
    return (
      <div className="bg-surface rounded-[var(--radius-lg)] shadow-card overflow-hidden">
        <table className="w-full">
          <thead>
            <tr className="border-b border-divider">
              {columns.map((col) => (
                <th key={col.id} className="px-4 py-3 text-left text-xs font-semibold text-text-secondary uppercase tracking-wider">
                  {col.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {Array.from({ length: 5 }).map((_, i) => (
              <tr key={i} className="border-b border-divider/50">
                {columns.map((col) => (
                  <td key={col.id} className="px-4 py-3">
                    <Skeleton className="h-4 w-24" />
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );
  }

  if (data.length === 0 && emptyState) {
    return <>{emptyState}</>;
  }

  return (
    <div>
      <div className="bg-surface rounded-[var(--radius-lg)] shadow-card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-divider">
                {table.getHeaderGroups().map((headerGroup) =>
                  headerGroup.headers.map((header) => (
                    <th
                      key={header.id}
                      className={`px-4 py-3 text-left text-xs font-semibold text-text-secondary uppercase tracking-wider ${
                        header.column.getCanSort() ? 'cursor-pointer select-none hover:text-charcoal' : ''
                      } ${(header.column.columnDef.meta as { className?: string })?.className ?? ''}`}
                      onClick={header.column.getToggleSortingHandler()}
                    >
                      <span className="inline-flex items-center gap-1">
                        {flexRender(header.column.columnDef.header, header.getContext())}
                        {header.column.getIsSorted() === 'asc' && <span className="text-rose-pink">↑</span>}
                        {header.column.getIsSorted() === 'desc' && <span className="text-rose-pink">↓</span>}
                      </span>
                    </th>
                  ))
                )}
              </tr>
            </thead>
            <tbody>
              {table.getRowModel().rows.map((row) => (
                <tr
                  key={row.id}
                  className={`border-b border-divider/50 last:border-b-0 ${
                    onRowClick ? 'cursor-pointer hover:bg-background/50 transition-colors' : ''
                  }`}
                  onClick={() => onRowClick?.(row.original)}
                >
                  {row.getVisibleCells().map((cell) => (
                    <td
                      key={cell.id}
                      className={`px-4 py-3 text-sm text-charcoal ${
                        (cell.column.columnDef.meta as { className?: string })?.className ?? ''
                      }`}
                    >
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {table.getPageCount() > 1 && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-sm text-text-secondary">
            Page {table.getState().pagination.pageIndex + 1} of {table.getPageCount()} ({data.length} total)
          </p>
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => table.previousPage()}
              disabled={!table.getCanPreviousPage()}
            >
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => table.nextPage()}
              disabled={!table.getCanNextPage()}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
}
