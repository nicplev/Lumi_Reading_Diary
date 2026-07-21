import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getSchool } from "@/lib/firestore/schools";
import { getReadingLog, listReadingLogs } from "@/lib/firestore/reading-logs";
import { listClasses } from "@/lib/firestore/classes";
import { listStudents } from "@/lib/firestore/students";
import { ReadingLogsList } from "./reading-logs-list";

export default async function ReadingLogsPage({
  params,
  searchParams,
}: {
  params: Promise<{ schoolId: string }>;
  searchParams: Promise<{ logId?: string }>;
}) {
  const { schoolId } = await params;
  const { logId: rawLogId } = await searchParams;
  const logId =
    rawLogId && rawLogId.length <= 256 && !rawLogId.includes("/")
      ? rawLogId
      : undefined;

  const [school, logs, classes, students, selectedLog] = await Promise.all([
    getSchool(schoolId),
    listReadingLogs(schoolId),
    listClasses(schoolId),
    listStudents(schoolId),
    logId ? getReadingLog(schoolId, logId) : null,
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
        initialDetailLog={selectedLog}
      />
    </>
  );
}
