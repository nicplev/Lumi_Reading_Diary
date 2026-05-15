"use client";

import { useState } from "react";
import { type ColumnDef } from "@tanstack/react-table";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { DataTable } from "@/components/data-table/data-table";
import { formatDateTime } from "@/lib/utils";
import type { AuditLogEntry } from "@/lib/firestore/audit-log";

interface AuditLogViewerProps {
  initialLogs: AuditLogEntry[];
}

const targetTypes = [
  "all",
  "school",
  "schoolUser",
  "student",
  "class",
  "book",
  "allocation",
  "linkCode",
  "schoolCode",
  "onboarding",
];

export function AuditLogViewer({ initialLogs }: AuditLogViewerProps) {
  const [filterType, setFilterType] = useState("all");
  const [searchEmail, setSearchEmail] = useState("");
  const [detailLog, setDetailLog] = useState<AuditLogEntry | null>(null);

  const filtered = initialLogs.filter((log) => {
    if (filterType !== "all" && log.targetType !== filterType) return false;
    if (
      searchEmail &&
      !(log.performedByEmail ?? "")
        .toLowerCase()
        .includes(searchEmail.toLowerCase())
    )
      return false;
    return true;
  });

  const columns: ColumnDef<AuditLogEntry, unknown>[] = [
    {
      accessorKey: "createdAt",
      header: "Time",
      cell: ({ row }) => (
        <span className="text-xs">{formatDateTime(row.original.createdAt)}</span>
      ),
    },
    {
      accessorKey: "action",
      header: "Action",
      cell: ({ row }) => (
        <code className="rounded bg-muted px-1.5 py-0.5 text-xs">
          {row.original.action}
        </code>
      ),
    },
    {
      accessorKey: "performedByEmail",
      header: "Admin",
      cell: ({ row }) =>
        row.original.performedByEmail ?? row.original.performedBy,
    },
    {
      accessorKey: "targetType",
      header: "Target",
      cell: ({ row }) => (
        <span className="capitalize">{row.original.targetType}</span>
      ),
    },
    {
      accessorKey: "targetId",
      header: "Target ID",
      cell: ({ row }) => (
        <span className="font-mono text-xs">
          {row.original.targetId.slice(0, 12)}...
        </span>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-4">
        <div className="space-y-2">
          <Label>Target Type</Label>
          <Select
            value={filterType}
            onValueChange={(v) => v && setFilterType(v)}
          >
            <SelectTrigger className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {targetTypes.map((t) => (
                <SelectItem key={t} value={t}>
                  {t === "all" ? "All types" : t}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Admin Email</Label>
          <Input
            value={searchEmail}
            onChange={(e) => setSearchEmail(e.target.value)}
            placeholder="Filter by email..."
            className="w-[220px]"
          />
        </div>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        searchKey="action"
        searchPlaceholder="Search actions..."
        onRowClick={setDetailLog}
      />

      <Dialog
        open={!!detailLog}
        onOpenChange={(open) => {
          if (!open) setDetailLog(null);
        }}
      >
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Audit Log Detail</DialogTitle>
          </DialogHeader>
          {detailLog && (
            <div className="space-y-4 pt-2">
              <div className="grid gap-3 sm:grid-cols-2">
                <div>
                  <p className="text-sm text-muted-foreground">Action</p>
                  <code className="text-sm">{detailLog.action}</code>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Time</p>
                  <p className="text-sm">{formatDateTime(detailLog.createdAt)}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Admin</p>
                  <p className="text-sm">
                    {detailLog.performedByEmail ?? detailLog.performedBy}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Target Type</p>
                  <p className="text-sm capitalize">{detailLog.targetType}</p>
                </div>
                <div className="sm:col-span-2">
                  <p className="text-sm text-muted-foreground">Target ID</p>
                  <p className="font-mono text-xs">{detailLog.targetId}</p>
                </div>
                {detailLog.schoolId && (
                  <div className="sm:col-span-2">
                    <p className="text-sm text-muted-foreground">School ID</p>
                    <p className="font-mono text-xs">{detailLog.schoolId}</p>
                  </div>
                )}
              </div>
              {detailLog.after && (
                <div>
                  <p className="text-sm text-muted-foreground">Data</p>
                  <pre className="mt-1 max-h-60 overflow-auto rounded-md bg-muted p-3 text-xs">
                    {JSON.stringify(detailLog.after, null, 2)}
                  </pre>
                </div>
              )}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
