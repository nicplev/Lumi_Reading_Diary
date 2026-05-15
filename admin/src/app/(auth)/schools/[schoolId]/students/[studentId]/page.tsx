import { notFound } from "next/navigation";
import { PageHeader } from "@/components/layout/page-header";
import { getStudent, getReadingLevelEvents } from "@/lib/firestore/students";
import { getStudentLinkCodes } from "@/lib/firestore/link-codes";
import { listClasses } from "@/lib/firestore/classes";
import { StudentDetailView } from "./student-detail-view";
import { ReadingLevelHistory } from "./reading-level-history";

export default async function StudentDetailPage({
  params,
}: {
  params: Promise<{ schoolId: string; studentId: string }>;
}) {
  const { schoolId, studentId } = await params;

  const [student, levelEvents, linkCodes, classes] = await Promise.all([
    getStudent(schoolId, studentId),
    getReadingLevelEvents(schoolId, studentId),
    getStudentLinkCodes(studentId),
    listClasses(schoolId),
  ]);

  if (!student) notFound();

  return (
    <>
      <PageHeader
        title={`${student.firstName} ${student.lastName}`}
        description={student.studentId ? `ID: ${student.studentId}` : undefined}
      />
      <div className="space-y-6">
        <StudentDetailView
          student={student}
          linkCodes={linkCodes}
          classes={classes}
          schoolId={schoolId}
        />
        <ReadingLevelHistory
          events={levelEvents}
          schoolId={schoolId}
          studentId={studentId}
        />
      </div>
    </>
  );
}
