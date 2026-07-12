"use client";

import Link from "next/link";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { StatusBadge } from "@/components/shared/status-badge";
import { RecentActivityTable } from "@/app/(auth)/recent-activity-table";
import { formatRelative } from "@/lib/utils";
import type { DashboardPayload } from "@/lib/dashboard/types";

export function ActivityFeedTabs({
  activity,
}: {
  activity: DashboardPayload["activity"];
}) {
  // RecentActivityTable's columns format createdAt via formatDateTime,
  // which accepts either type — only the prop type wants a Date.
  const logs = activity.readingLogs.map((log) => ({
    ...log,
    createdAt: new Date(log.createdAt),
  }));

  return (
    <Tabs defaultValue="logs">
      <TabsList>
        <TabsTrigger value="logs">Reading logs</TabsTrigger>
        <TabsTrigger value="admin">Admin actions</TabsTrigger>
        <TabsTrigger value="pipeline">Pipeline & feedback</TabsTrigger>
      </TabsList>

      <TabsContent value="logs">
        <RecentActivityTable data={logs} />
      </TabsContent>

      <TabsContent value="admin">
        {activity.adminActions.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">
            No recent admin actions.
          </p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Action</TableHead>
                <TableHead>By</TableHead>
                <TableHead>Target</TableHead>
                <TableHead>School</TableHead>
                <TableHead>When</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {activity.adminActions.map((entry) => (
                <TableRow key={entry.id}>
                  <TableCell className="font-mono text-xs">
                    {entry.action}
                  </TableCell>
                  <TableCell className="text-xs">
                    {entry.performedByEmail ?? "system"}
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {entry.targetType}/{entry.targetId}
                  </TableCell>
                  <TableCell className="font-mono text-xs">
                    {entry.schoolId ?? "—"}
                  </TableCell>
                  <TableCell className="text-xs">
                    {formatRelative(entry.createdAt)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </TabsContent>

      <TabsContent value="pipeline">
        {activity.pipeline.length === 0 ? (
          <p className="py-4 text-sm text-muted-foreground">
            No recent onboarding requests or feedback.
          </p>
        ) : (
          <div className="space-y-1">
            {activity.pipeline.map((item) => (
              <Link
                key={`${item.type}-${item.id}`}
                href={item.href}
                className="flex items-center justify-between gap-2 rounded-md px-2 py-1.5 text-sm hover:bg-muted"
              >
                <span className="flex min-w-0 items-center gap-2">
                  <span className="shrink-0 text-xs uppercase text-muted-foreground">
                    {item.type}
                  </span>
                  <span className="truncate">{item.title}</span>
                </span>
                <span className="flex shrink-0 items-center gap-2">
                  <StatusBadge status={item.status} />
                  <span className="text-xs text-muted-foreground">
                    {formatRelative(item.createdAt)}
                  </span>
                </span>
              </Link>
            ))}
          </div>
        )}
      </TabsContent>
    </Tabs>
  );
}
