"use client";

import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import type { SchoolDetail, SchoolStats } from "@/lib/firestore/schools";
import type { SchoolUserListItem } from "@/lib/firestore/school-users";
import type { StudentListItem } from "@/lib/firestore/students";
import type { ClassListItem } from "@/lib/firestore/classes";
import type { ParentListItem } from "@/lib/firestore/parents";
import { SchoolOverview } from "./school-overview";
import { SchoolForm } from "./school-form";
import { ReadingLevelConfig } from "./reading-level-config";
import { SchoolUsersTab } from "./school-users-tab";
import { SchoolStudentsTab } from "./school-students-tab";
import { SchoolClassesTab } from "./school-classes-tab";
import { SchoolParentsTab } from "./school-parents-tab";
import { SchoolSubscriptionTab } from "./school-subscription-tab";
import type { SchoolSubscriptionRow } from "@/lib/firestore/school-subscriptions";

interface SchoolDetailTabsProps {
  school: SchoolDetail;
  stats: SchoolStats;
  users: SchoolUserListItem[];
  students: StudentListItem[];
  classes: ClassListItem[];
  parents: ParentListItem[];
  defaultTab?: string;
  bookCount?: number;
  activeAllocationCount?: number;
  recentLogCount?: number;
  subscriptions: SchoolSubscriptionRow[];
  currentAcademicYear: number;
}

export function SchoolDetailTabs({
  school,
  stats,
  users,
  students,
  classes,
  parents,
  defaultTab,
  bookCount,
  activeAllocationCount,
  recentLogCount,
  subscriptions,
  currentAcademicYear,
}: SchoolDetailTabsProps) {
  return (
    <Tabs defaultValue={defaultTab || "overview"} className="space-y-4">
      <TabsList>
        <TabsTrigger value="overview">Overview</TabsTrigger>
        <TabsTrigger value="subscription">Subscription</TabsTrigger>
        <TabsTrigger value="settings">Settings</TabsTrigger>
        <TabsTrigger value="levels">Reading Levels</TabsTrigger>
        <TabsTrigger value="users">Users</TabsTrigger>
        <TabsTrigger value="students">Students</TabsTrigger>
        <TabsTrigger value="classes">Classes</TabsTrigger>
        <TabsTrigger value="parents">Parents</TabsTrigger>
      </TabsList>
      <TabsContent value="overview">
        <SchoolOverview
          school={school}
          stats={stats}
          bookCount={bookCount}
          activeAllocationCount={activeAllocationCount}
          recentLogCount={recentLogCount}
        />
      </TabsContent>
      <TabsContent value="subscription">
        <SchoolSubscriptionTab
          schoolId={school.id}
          studentCount={stats.studentCount}
          currentAcademicYear={currentAcademicYear}
          initialSubscriptions={subscriptions}
        />
      </TabsContent>
      <TabsContent value="settings">
        <SchoolForm school={school} />
      </TabsContent>
      <TabsContent value="levels">
        <ReadingLevelConfig school={school} />
      </TabsContent>
      <TabsContent value="users">
        <SchoolUsersTab schoolId={school.id} users={users} />
      </TabsContent>
      <TabsContent value="students">
        <SchoolStudentsTab
          schoolId={school.id}
          students={students}
          classes={classes}
        />
      </TabsContent>
      <TabsContent value="classes">
        <SchoolClassesTab
          schoolId={school.id}
          classes={classes}
          users={users}
        />
      </TabsContent>
      <TabsContent value="parents">
        <SchoolParentsTab schoolId={school.id} parents={parents} />
      </TabsContent>
    </Tabs>
  );
}
