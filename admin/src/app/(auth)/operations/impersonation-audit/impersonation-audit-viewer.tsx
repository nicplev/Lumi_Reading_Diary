"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
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
import { DataTable } from "@/components/data-table/data-table";
import { formatDateTime } from "@/lib/utils";
import type {
  ImpersonationSession,
  ImpersonationStatus,
} from "@/lib/firestore/impersonation-audit";

interface Props {
  initialSessions: ImpersonationSession[];
}

const STATUS_OPTIONS: Array<"all" | ImpersonationStatus> = [
  "all",
  "active",
  "ended",
  "expired",
  "revoked",
];

function durationLabel(s: ImpersonationSession): string {
  if (s.status === "active") {
    const m = Math.floor((s.remainingMs ?? 0) / 60_000);
    return `active · ${m}m left`;
  }
  if (!s.startedAt || !s.endedAt) return s.status;
  const start = new Date(s.startedAt).getTime();
  const end = new Date(s.endedAt).getTime();
  if (isNaN(start) || isNaN(end)) return s.status;
  const mins = Math.round((end - start) / 60_000);
  return `${mins} min · ${s.status}`;
}

export function ImpersonationAuditViewer({ initialSessions }: Props) {
  const [sessions] = useState<ImpersonationSession[]>(initialSessions);
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [searchEmail, setSearchEmail] = useState("");
  const [searchSchool, setSearchSchool] = useState("");

  const filtered = useMemo(() => {
    return sessions.filter((s) => {
      if (filterStatus !== "all" && s.status !== filterStatus) return false;
      if (
        searchEmail &&
        !s.devEmail.toLowerCase().includes(searchEmail.toLowerCase())
      )
        return false;
      if (searchSchool) {
        const q = searchSchool.toLowerCase();
        const inName = (s.targetSchoolName ?? "").toLowerCase().includes(q);
        const inId = s.targetSchoolId.toLowerCase().includes(q);
        if (!inName && !inId) return false;
      }
      return true;
    });
  }, [sessions, filterStatus, searchEmail, searchSchool]);

  const columns: ColumnDef<ImpersonationSession, unknown>[] = [
    {
      accessorKey: "startedAt",
      header: "Started",
      cell: ({ row }) => (
        <span className="text-xs">{formatDateTime(row.original.startedAt)}</span>
      ),
    },
    {
      accessorKey: "devEmail",
      header: "Developer",
      cell: ({ row }) => (
        <span className="text-sm">{row.original.devEmail}</span>
      ),
    },
    {
      accessorKey: "targetSchoolName",
      header: "School",
      cell: ({ row }) => (
        <span className="text-sm">
          {row.original.targetSchoolName ?? row.original.targetSchoolId}
        </span>
      ),
    },
    {
      accessorKey: "targetRole",
      header: "Role",
      cell: ({ row }) => (
        <span className="text-xs capitalize">{row.original.targetRole}</span>
      ),
    },
    {
      accessorKey: "targetUserEmail",
      header: "Target user",
      cell: ({ row }) => (
        <span className="text-xs">
          {row.original.targetUserEmail ?? row.original.targetUserId}
        </span>
      ),
    },
    {
      accessorKey: "status",
      header: "Status / duration",
      cell: ({ row }) => {
        const s = row.original;
        const color =
          s.status === "active"
            ? "text-green-700"
            : s.status === "revoked"
              ? "text-red-700"
              : "text-muted-foreground";
        return (
          <span className={`text-xs font-medium ${color}`}>
            {durationLabel(s)}
          </span>
        );
      },
    },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <Link
          href={`/operations/impersonation-audit/${row.original.id}`}
          className="text-xs text-primary underline-offset-4 hover:underline"
          onClick={(e) => e.stopPropagation()}
        >
          View →
        </Link>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-4">
        <div className="space-y-2">
          <Label>Status</Label>
          <Select
            value={filterStatus}
            onValueChange={(v) => v && setFilterStatus(v)}
          >
            <SelectTrigger className="w-[160px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {STATUS_OPTIONS.map((s) => (
                <SelectItem key={s} value={s}>
                  {s === "all" ? "All statuses" : s}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-2">
          <Label>Developer email</Label>
          <Input
            value={searchEmail}
            onChange={(e) => setSearchEmail(e.target.value)}
            placeholder="Filter by dev email..."
            className="w-[220px]"
          />
        </div>
        <div className="space-y-2">
          <Label>School</Label>
          <Input
            value={searchSchool}
            onChange={(e) => setSearchSchool(e.target.value)}
            placeholder="Name or ID..."
            className="w-[220px]"
          />
        </div>
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        searchKey="reason"
        searchPlaceholder="Search reason text..."
      />

      <p className="text-xs text-muted-foreground">
        Showing {filtered.length} of {sessions.length} sessions. Click a row to
        inspect every event, revoke, or export the trail.
      </p>
    </div>
  );
}
