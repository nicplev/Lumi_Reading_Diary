import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool, getSchoolStats } from "@/lib/firestore/schools";
import { listSchoolUsers } from "@/lib/firestore/school-users";
import { listStudents } from "@/lib/firestore/students";
import { listClasses } from "@/lib/firestore/classes";
import { listParents } from "@/lib/firestore/parents";
import { getBookCount } from "@/lib/firestore/books";
import { getActiveAllocationCount } from "@/lib/firestore/allocations";
import { getReadingLogCountForSchool } from "@/lib/firestore/reading-logs";
import {
  getCurrentAcademicYear,
  getSubscriptionsForSchool,
} from "@/lib/firestore/school-subscriptions";
import { isDemoSchool, listAllDemoAccessEmails } from "@/lib/firestore/demo-access";
import { SchoolDetailTabs } from "./school-detail-tabs";

export default async function SchoolDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ schoolId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { schoolId } = await params;
  const { tab } = await searchParams;

  const [school, stats, users, students, classes, parents, bookCount, activeAllocationCount, recentLogCount, subscriptions, currentAcademicYear, isDemo] = await Promise.all([
    getSchool(schoolId),
    getSchoolStats(schoolId),
    listSchoolUsers(schoolId),
    listStudents(schoolId),
    listClasses(schoolId),
    listParents(schoolId),
    getBookCount(schoolId),
    getActiveAllocationCount(schoolId),
    getReadingLogCountForSchool(schoolId),
    getSubscriptionsForSchool(schoolId),
    getCurrentAcademicYear(),
    isDemoSchool(schoolId),
  ]);

  if (!school) notFound();

  // Demo-access send history is the canonical "who has been given demo access"
  // view — shown only on the demo school's page.
  const demoAccessEmails = isDemo ? await listAllDemoAccessEmails() : null;

  return (
    <>
      <PageHeader
        title={school.name}
        description={school.contactEmail || undefined}
      />
      <SchoolDetailTabs
        school={school}
        stats={stats}
        users={users}
        students={students}
        classes={classes}
        parents={parents}
        defaultTab={tab}
        bookCount={bookCount}
        activeAllocationCount={activeAllocationCount}
        recentLogCount={recentLogCount}
        subscriptions={subscriptions}
        currentAcademicYear={currentAcademicYear}
        demoAccessEmails={demoAccessEmails}
      />
    </>
  );
}
