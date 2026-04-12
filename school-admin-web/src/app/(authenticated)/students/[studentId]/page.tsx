import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getStudent } from '@/lib/firestore/students';
import { getSchool } from '@/lib/firestore/school';
import { getClass } from '@/lib/firestore/classes';
import { getReadingLevels } from '@/lib/types';
import { StudentDetail } from './student-detail';
import type { ReadingLevelOption } from '@/lib/types';

export default async function StudentDetailRoute({ params }: { params: Promise<{ studentId: string }> }) {
  const session = await getSession();
  if (!session) redirect('/login');

  const { studentId } = await params;
  const [student, school] = await Promise.all([
    getStudent(session.schoolId, studentId),
    getSchool(session.schoolId),
  ]);

  if (!student) redirect('/students');

  const schoolClass = student.classId ? await getClass(session.schoolId, student.classId) : null;

  const levels = getReadingLevels(school?.levelSchema ?? 'aToZ', school?.customLevels);
  const levelOptions: ReadingLevelOption[] = levels.map((level, i) => ({
    value: level,
    shortLabel: level,
    displayLabel: level,
    sortIndex: i,
    schema: school?.levelSchema ?? 'aToZ',
    colorHex: school?.levelColors?.[level],
  }));

  return (
    <StudentDetail
      studentId={studentId}
      classId={student.classId}
      levelOptions={levelOptions}
      className={schoolClass?.name}
    />
  );
}
