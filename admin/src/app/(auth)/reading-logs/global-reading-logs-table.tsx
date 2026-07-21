"use client";

import Link from "next/link";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useState } from "react";
import { toast } from "sonner";
import { type ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table/data-table";
import { StatusBadge } from "@/components/shared/status-badge";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { formatDate } from "@/lib/utils";
import type { GlobalReadingLogItem } from "@/lib/firestore/reading-logs";

type ReviewFilter = "open" | "all";
type PeriodFilter = "today" | "7d";
type ValidationAction = "revalidate" | "acknowledge" | "delete";

interface Props {
  logs: GlobalReadingLogItem[];
  validationMode: boolean;
  reviewFilter: ReviewFilter;
  period: PeriodFilter;
}

export function GlobalReadingLogsTable({
  logs,
  validationMode,
  reviewFilter: initialReview,
  period: initialPeriod,
}: Props) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [reviewFilter, setReviewFilter] = useState<ReviewFilter>(initialReview);
  const [period, setPeriod] = useState<PeriodFilter>(initialPeriod);
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<GlobalReadingLogItem | null>(null);

  const updateReviewFilter = (next: ReviewFilter) => {
    setReviewFilter(next);
    const params = new URLSearchParams(searchParams.toString());
    params.set("review", next);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const updatePeriod = (next: PeriodFilter) => {
    setPeriod(next);
    const params = new URLSearchParams(searchParams.toString());
    params.set("period", next);
    router.replace(`${pathname}?${params.toString()}`, { scroll: false });
  };

  const runAction = async (
    log: GlobalReadingLogItem,
    action: ValidationAction
  ) => {
    setLoadingId(log.id);
    try {
      const response = await fetch("/api/reading-log-validation/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ schoolId: log.schoolId, logId: log.id, action }),
      });
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? "Action failed");
      if (action === "revalidate") {
        toast.success(
          body.valid
            ? "Log passed validation and was restored to statistics"
            : "Validation rerun; the log remains excluded"
        );
      } else if (action === "acknowledge") {
        toast.success("Log acknowledged and left excluded");
      } else {
        toast.success("Invalid log permanently deleted");
      }
      setDeleteTarget(null);
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : "Action failed");
    } finally {
      setLoadingId(null);
    }
  };

  const columns: ColumnDef<GlobalReadingLogItem, unknown>[] = [
    {
      accessorKey: "schoolName",
      header: "School",
      cell: ({ row }) => (
        <Link
          href={`/schools/${encodeURIComponent(row.original.schoolId)}`}
          className="font-medium text-primary hover:underline"
          onClick={(event) => event.stopPropagation()}
        >
          {row.original.schoolName ?? "—"}
        </Link>
      ),
    },
    {
      accessorKey: "studentName",
      header: "Student",
      cell: ({ row }) => (
        <Link
          href={`/schools/${encodeURIComponent(row.original.schoolId)}/students/${encodeURIComponent(row.original.studentId)}`}
          className="hover:underline"
          onClick={(event) => event.stopPropagation()}
        >
          {row.original.studentName || row.original.studentId}
        </Link>
      ),
    },
    {
      accessorKey: "date",
      header: "Date",
      cell: ({ row }) => formatDate(row.original.date),
    },
    {
      accessorKey: "minutesRead",
      header: "Minutes",
      cell: ({ row }) => `${row.original.minutesRead} min`,
    },
    {
      accessorKey: "bookTitles",
      header: "Books",
      cell: ({ row }) => {
        const titles = row.original.bookTitles;
        if (!titles.length) return "—";
        const value = titles.join(", ");
        return value.length > 30 ? `${value.slice(0, 30)}...` : value;
      },
    },
    ...(validationMode
      ? ([
          {
            id: "validationErrors",
            header: "Validation issue",
            cell: ({ row }) => (
              <div className="max-w-[360px] space-y-1 text-sm">
                {row.original.validationErrors.length > 0
                  ? row.original.validationErrors.map((error) => (
                      <p key={error}>{error}</p>
                    ))
                  : "Invalid without a stored reason"}
              </div>
            ),
          },
          {
            accessorKey: "validationReviewStatus",
            header: "Review",
            cell: ({ row }) => (
              <StatusBadge status={row.original.validationReviewStatus} />
            ),
          },
          {
            id: "actions",
            header: "",
            cell: ({ row }) => (
              <div
                className="flex justify-end gap-1"
                onClick={(event) => event.stopPropagation()}
              >
                <Button
                  variant="outline"
                  size="sm"
                  disabled={loadingId === row.original.id}
                  onClick={() => runAction(row.original, "revalidate")}
                >
                  Re-run validation
                </Button>
                {row.original.validationReviewStatus === "open" && (
                  <Button
                    variant="ghost"
                    size="sm"
                    disabled={loadingId === row.original.id}
                    onClick={() => runAction(row.original, "acknowledge")}
                  >
                    Keep excluded
                  </Button>
                )}
                <Button
                  variant="destructive"
                  size="sm"
                  disabled={loadingId === row.original.id}
                  onClick={() => setDeleteTarget(row.original)}
                >
                  Delete
                </Button>
              </div>
            ),
          },
        ] satisfies ColumnDef<GlobalReadingLogItem, unknown>[])
      : ([
          {
            accessorKey: "status",
            header: "Status",
            cell: ({ row }) => <StatusBadge status={row.original.status} />,
          },
        ] satisfies ColumnDef<GlobalReadingLogItem, unknown>[])),
  ];

  return (
    <div className="space-y-4">
      {validationMode && (
        <div className="flex flex-wrap items-center gap-3">
          <Select
            value={reviewFilter}
            onValueChange={(value) =>
              value && updateReviewFilter(value as ReviewFilter)
            }
          >
            <SelectTrigger className="w-[210px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="open">Open review items</SelectItem>
              <SelectItem value="all">All invalid logs</SelectItem>
            </SelectContent>
          </Select>
          <span className="text-sm text-muted-foreground">
            {logs.length} log{logs.length === 1 ? "" : "s"}
          </span>
        </div>
      )}
      {!validationMode && (
        <div className="flex flex-wrap items-center gap-3">
          <Select
            value={period}
            onValueChange={(value) =>
              value && updatePeriod(value as PeriodFilter)
            }
          >
            <SelectTrigger className="w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="today">Today</SelectItem>
              <SelectItem value="7d">Last 7 days</SelectItem>
            </SelectContent>
          </Select>
          <span className="text-sm text-muted-foreground">
            {logs.length} log{logs.length === 1 ? "" : "s"}
          </span>
        </div>
      )}

      <DataTable
        columns={columns}
        data={logs}
        searchKey="schoolName"
        searchPlaceholder="Search by school..."
      />

      <ConfirmDialog
        open={deleteTarget !== null}
        onOpenChange={(open) => {
          if (!open && !loadingId) setDeleteTarget(null);
        }}
        title="Permanently delete invalid log?"
        description="The reading log and its child records will be deleted. Any comprehension recording is removed first. This cannot be undone."
        confirmLabel="Delete log"
        variant="destructive"
        onConfirm={() => deleteTarget && runAction(deleteTarget, "delete")}
        loading={deleteTarget ? loadingId === deleteTarget.id : false}
      />
    </div>
  );
}
