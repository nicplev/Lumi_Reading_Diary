import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { listReadingLogs } from "@/lib/firestore/reading-logs";
import { listClasses } from "@/lib/firestore/classes";
import { listStudents } from "@/lib/firestore/students";
import { ReadingLogsList } from "./reading-logs-list";

export default async function ReadingLogsPage({
  params,
}: {
  params: Promise<{ schoolId: string }>;
}) {
  const { schoolId } = await params;

  const [school, logs, classes, students] = await Promise.all([
    getSchool(schoolId),
    listReadingLogs(schoolId),
    listClasses(schoolId),
    listStudents(schoolId),
  ]);

  if (!school) notFound();

  return (
    <>
      <PageHeader
        title={`${school.name} - Reading Logs`}
        description="Last 7 days"
      />
      <ReadingLogsList
        schoolId={schoolId}
        initialLogs={logs}
        classes={classes}
        students={students}
      />
    </>
  );
}
