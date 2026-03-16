"use client";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { SchoolDetail, SchoolStats } from "@/lib/firestore/schools";
import { SchoolOverview } from "./school-overview";
import { SchoolForm } from "./school-form";
import { ReadingLevelConfig } from "./reading-level-config";

interface SchoolDetailTabsProps {
  school: SchoolDetail;
  stats: SchoolStats;
}

export function SchoolDetailTabs({ school, stats }: SchoolDetailTabsProps) {
  return (
    <Tabs defaultValue="overview" className="space-y-4">
      <TabsList>
        <TabsTrigger value="overview">Overview</TabsTrigger>
        <TabsTrigger value="settings">Settings</TabsTrigger>
        <TabsTrigger value="levels">Reading Levels</TabsTrigger>
      </TabsList>
      <TabsContent value="overview">
        <SchoolOverview school={school} stats={stats} />
      </TabsContent>
      <TabsContent value="settings">
        <SchoolForm school={school} />
      </TabsContent>
      <TabsContent value="levels">
        <ReadingLevelConfig school={school} />
      </TabsContent>
    </Tabs>
  );
}
