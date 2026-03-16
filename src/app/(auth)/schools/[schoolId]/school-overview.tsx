"use client";

import { Users, GraduationCap, UserCheck } from "lucide-react";
import { StatCard } from "@/components/cards/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/shared/status-badge";
import type { SchoolDetail, SchoolStats } from "@/lib/firestore/schools";

interface SchoolOverviewProps {
  school: SchoolDetail;
  stats: SchoolStats;
}

export function SchoolOverview({ school, stats }: SchoolOverviewProps) {
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
              {school.createdAt
                ? new Date(school.createdAt).toLocaleDateString()
                : "\u2014"}
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
