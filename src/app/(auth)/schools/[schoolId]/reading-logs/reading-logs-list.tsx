"use client";

import { useState } from "react";
import { type ColumnDef } from "@tanstack/react-table";
import { MessageSquare, User } from "lucide-react";
import { Button } from "@/components/ui/button";
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
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import type { ReadingLogListItem, ReadingLogDetail } from "@/lib/firestore/reading-logs";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { StudentListItem } from "@/lib/firestore/students";

interface ReadingLogsListProps {
  schoolId: string;
  initialLogs: ReadingLogListItem[];
  classes: ClassListItem[];
  students: StudentListItem[];
}

export function ReadingLogsList({
  schoolId,
  initialLogs,
  classes,
  students,
}: ReadingLogsListProps) {
  const [logs, setLogs] = useState(initialLogs);
  const [loading, setLoading] = useState(false);
  const [filterClassId, setFilterClassId] = useState<string>("all");
  const [filterStatus, setFilterStatus] = useState<string>("all");
  const [startDate, setStartDate] = useState("");
  const [endDate, setEndDate] = useState("");
  const [detailLog, setDetailLog] = useState<ReadingLogDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const studentMap = new Map(
    students.map((s) => [s.id, `${s.firstName} ${s.lastName}`])
  );
  const classMap = new Map(classes.map((c) => [c.id, c.name]));

  const filteredLogs = logs.filter((log) => {
    if (filterClassId !== "all" && log.classId !== filterClassId) return false;
    if (filterStatus !== "all" && log.status !== filterStatus) return false;
    return true;
  });

  const handleDateFilter = async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams();
      if (startDate) params.set("startDate", startDate);
      if (endDate) params.set("endDate", endDate);

      const res = await fetch(
        `/api/schools/${schoolId}/reading-logs?${params.toString()}`
      );
      if (!res.ok) throw new Error("Failed to fetch logs");
      const data = await res.json();
      setLogs(data.logs);
    } catch {
      // Keep existing logs on error
    } finally {
      setLoading(false);
    }
  };

  const handleRowClick = async (log: ReadingLogListItem) => {
    setDetailLoading(true);
    setDetailLog(null);
    try {
      // Fetch full detail - use the list item data + fetch detail via GET with the log ID
      // Since we don't have a single-log GET endpoint, we'll construct from list data
      setDetailLog({
        ...log,
        notes: undefined,
        photoUrls: [],
        syncedAt: undefined,
        allocationId: undefined,
        parentComment: undefined,
        parentCommentSelections: [],
        parentCommentFreeText: undefined,
        teacherComment: undefined,
        commentedAt: undefined,
        commentedBy: undefined,
        metadata: undefined,
      });
    } finally {
      setDetailLoading(false);
    }
  };

  const columns: ColumnDef<ReadingLogListItem, unknown>[] = [
    {
      accessorKey: "studentId",
      header: "Student",
      cell: ({ row }) =>
        studentMap.get(row.original.studentId) ?? row.original.studentId,
    },
    {
      accessorKey: "classId",
      header: "Class",
      cell: ({ row }) =>
        row.original.classId
          ? classMap.get(row.original.classId) ?? "\u2014"
          : "\u2014",
    },
    {
      accessorKey: "date",
      header: "Date",
      cell: ({ row }) => formatDate(row.original.date),
    },
    {
      id: "minutes",
      header: "Minutes",
      cell: ({ row }) => {
        const { minutesRead, targetMinutes } = row.original;
        return targetMinutes
          ? `${minutesRead}/${targetMinutes} min`
          : `${minutesRead} min`;
      },
    },
    {
      accessorKey: "bookTitles",
      header: "Books",
      cell: ({ row }) => {
        const titles = row.original.bookTitles;
        if (!titles.length) return "\u2014";
        const text = titles.join(", ");
        return text.length > 30 ? text.slice(0, 30) + "..." : text;
      },
    },
    {
      accessorKey: "childFeeling",
      header: "Feeling",
      cell: ({ row }) =>
        row.original.childFeeling ? (
          <StatusBadge status={row.original.childFeeling} />
        ) : (
          "\u2014"
        ),
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      id: "comments",
      header: "Comments",
      cell: ({ row }) => (
        <div className="flex gap-1">
          {row.original.hasTeacherComment && (
            <MessageSquare className="h-4 w-4 text-blue-500" />
          )}
          {row.original.hasParentComment && (
            <User className="h-4 w-4 text-green-500" />
          )}
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-4">
        <div className="space-y-2">
          <Label>Start Date</Label>
          <Input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
          />
        </div>
        <div className="space-y-2">
          <Label>End Date</Label>
          <Input
            type="date"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
          />
        </div>
        <Button onClick={handleDateFilter} disabled={loading}>
          {loading ? "Loading..." : "Apply"}
        </Button>
        <Select
          value={filterClassId}
          onValueChange={(v) => v && setFilterClassId(v)}
        >
          <SelectTrigger className="w-[200px]">
            <SelectValue placeholder="All classes" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All classes</SelectItem>
            {classes.map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Select
          value={filterStatus}
          onValueChange={(v) => v && setFilterStatus(v)}
        >
          <SelectTrigger className="w-[160px]">
            <SelectValue placeholder="All statuses" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            <SelectItem value="completed">Completed</SelectItem>
            <SelectItem value="partial">Partial</SelectItem>
            <SelectItem value="skipped">Skipped</SelectItem>
            <SelectItem value="pending">Pending</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <DataTable
        columns={columns}
        data={filteredLogs}
        searchKey="studentId"
        searchPlaceholder="Search by student ID..."
        onRowClick={handleRowClick}
      />

      {/* Detail Dialog */}
      <Dialog
        open={!!detailLog}
        onOpenChange={(open) => {
          if (!open) setDetailLog(null);
        }}
      >
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Reading Log Detail</DialogTitle>
          </DialogHeader>
          {detailLoading ? (
            <p className="text-sm text-muted-foreground">Loading...</p>
          ) : detailLog ? (
            <div className="space-y-4 pt-2">
              <div className="grid gap-4 sm:grid-cols-2">
                <div>
                  <p className="text-sm text-muted-foreground">Student</p>
                  <p className="font-medium">
                    {studentMap.get(detailLog.studentId) ??
                      detailLog.studentId}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Class</p>
                  <p className="font-medium">
                    {detailLog.classId
                      ? classMap.get(detailLog.classId) ?? "\u2014"
                      : "\u2014"}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Date</p>
                  <p className="font-medium">{formatDate(detailLog.date)}</p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Minutes</p>
                  <p className="font-medium">
                    {detailLog.targetMinutes
                      ? `${detailLog.minutesRead}/${detailLog.targetMinutes} min`
                      : `${detailLog.minutesRead} min`}
                  </p>
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Status</p>
                  <StatusBadge status={detailLog.status} />
                </div>
                <div>
                  <p className="text-sm text-muted-foreground">Feeling</p>
                  {detailLog.childFeeling ? (
                    <StatusBadge status={detailLog.childFeeling} />
                  ) : (
                    <p className="font-medium">{"\u2014"}</p>
                  )}
                </div>
              </div>
              {detailLog.bookTitles.length > 0 && (
                <div>
                  <p className="text-sm text-muted-foreground">Books</p>
                  <p className="font-medium">
                    {detailLog.bookTitles.join(", ")}
                  </p>
                </div>
              )}
              {detailLog.notes && (
                <div>
                  <p className="text-sm text-muted-foreground">Notes</p>
                  <p className="font-medium">{detailLog.notes}</p>
                </div>
              )}
              {detailLog.parentComment && (
                <div>
                  <p className="text-sm text-muted-foreground">
                    Parent Comment
                  </p>
                  <p className="font-medium">{detailLog.parentComment}</p>
                  {detailLog.parentCommentSelections.length > 0 && (
                    <p className="text-sm text-muted-foreground">
                      Selections:{" "}
                      {detailLog.parentCommentSelections.join(", ")}
                    </p>
                  )}
                  {detailLog.parentCommentFreeText && (
                    <p className="text-sm">
                      {detailLog.parentCommentFreeText}
                    </p>
                  )}
                </div>
              )}
              {detailLog.teacherComment && (
                <div>
                  <p className="text-sm text-muted-foreground">
                    Teacher Comment
                  </p>
                  <p className="font-medium">{detailLog.teacherComment}</p>
                  {detailLog.commentedAt && (
                    <p className="text-sm text-muted-foreground">
                      at {formatDate(detailLog.commentedAt)}
                    </p>
                  )}
                </div>
              )}
              {detailLog.photoUrls.length > 0 && (
                <div>
                  <p className="text-sm text-muted-foreground">Photos</p>
                  <div className="flex flex-wrap gap-2">
                    {detailLog.photoUrls.map((url, i) => (
                      <a
                        key={i}
                        href={url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-blue-600 underline"
                      >
                        Photo {i + 1}
                      </a>
                    ))}
                  </div>
                </div>
              )}
              <div className="grid gap-4 sm:grid-cols-2 text-sm">
                {detailLog.allocationId && (
                  <div>
                    <p className="text-muted-foreground">Allocation ID</p>
                    <p className="font-mono text-xs">
                      {detailLog.allocationId}
                    </p>
                  </div>
                )}
                <div>
                  <p className="text-muted-foreground">Offline Created</p>
                  <p>{detailLog.isOfflineCreated ? "Yes" : "No"}</p>
                </div>
              </div>
            </div>
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  );
}
