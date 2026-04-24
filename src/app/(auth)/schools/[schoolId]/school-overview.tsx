"use client";

import Link from "next/link";
import { Users, GraduationCap, UserCheck, BookOpen, ClipboardList, BarChart3 } from "lucide-react";
import { StatCard } from "@/components/cards/stat-card";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDate } from "@/lib/utils";
import type { SchoolDetail, SchoolStats } from "@/lib/firestore/schools";

interface SchoolOverviewProps {
  school: SchoolDetail;
  stats: SchoolStats;
  bookCount?: number;
  activeAllocationCount?: number;
  recentLogCount?: number;
}

export function SchoolOverview({ school, stats, bookCount, activeAllocationCount, recentLogCount }: SchoolOverviewProps) {
  return (
    <div className="space-y-6">
      <div className="grid gap-4 md:grid-cols-3">
        <StatCard
          title="Students"
          value={stats.studentCount}
          icon={GraduationCap}
        />
        <StatCard title="Teachers" value={stats.teacherCount} icon={Users} />
        <StatCard
          title="Parents"
          value={stats.parentCount}
          icon={UserCheck}
        />
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <StatCard
          title="Books"
          value={bookCount ?? 0}
          icon={BookOpen}
        />
        <StatCard
          title="Active Allocations"
          value={activeAllocationCount ?? 0}
          icon={ClipboardList}
        />
        <StatCard
          title="Reading Logs (7d)"
          value={recentLogCount ?? 0}
          icon={BarChart3}
        />
      </div>

      <div className="flex flex-wrap gap-2">
        <Link href={`/schools/${school.id}/library`}>
          <Button variant="outline">View Library</Button>
        </Link>
        <Link href={`/schools/${school.id}/allocations`}>
          <Button variant="outline">View Allocations</Button>
        </Link>
        <Link href={`/schools/${school.id}/reading-logs`}>
          <Button variant="outline">View Reading Logs</Button>
        </Link>
        <Link href={`/schools/${school.id}/analytics`}>
          <Button variant="outline">View Analytics</Button>
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>School Information</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div>
            <p className="text-sm text-muted-foreground">Status</p>
            <StatusBadge
              status={school.isActive ? "active" : "suspended"}
            />
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Timezone</p>
            <p className="font-medium">{school.timezone}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Contact Email</p>
            <p className="font-medium">{school.contactEmail || "\u2014"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Contact Phone</p>
            <p className="font-medium">{school.contactPhone || "\u2014"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Address</p>
            <p className="font-medium">{school.address || "\u2014"}</p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Subscription</p>
            <p className="font-medium">
              {school.subscriptionPlan || "\u2014"}
            </p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">
              Reading Level Schema
            </p>
            <p className="font-medium capitalize">
              {school.levelSchema.replace(/([A-Z])/g, " $1")}
            </p>
          </div>
          <div>
            <p className="text-sm text-muted-foreground">Created</p>
            <p className="font-medium">
              {formatDate(school.createdAt)}
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
