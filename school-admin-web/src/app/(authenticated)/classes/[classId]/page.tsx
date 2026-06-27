import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClass, getClasses } from '@/lib/firestore/classes';
import { getSchool } from '@/lib/firestore/school';
import { getReadingLevels } from '@/lib/types';
import { ClassDetail } from './class-detail';
import type { ReadingLevelOption } from '@/lib/types';

export default async function ClassDetailRoute({ params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) redirect('/login');

  const isTeacher = session.role === 'teacher';
  const { classId } = await params;
  const [schoolClass, school, myClasses] = await Promise.all([
    getClass(session.schoolId, classId),
    getSchool(session.schoolId),
    // Power the teacher class switcher; admins navigate via the Classes list.
    isTeacher ? getClasses(session.schoolId, { teacherId: session.uid }) : Promise.resolve([]),
  ]);

  if (!schoolClass) redirect('/classes');

  const levelsEnabled = (school?.levelSchema ?? 'aToZ') !== 'none';
  const levels = getReadingLevels(school?.levelSchema ?? 'aToZ', school?.customLevels);
  const levelOptions: ReadingLevelOption[] = levels.map((level, i) => ({
    value: level,
    shortLabel: level,
    displayLabel: level,
    sortIndex: i,
    schema: school?.levelSchema ?? 'aToZ',
    colorHex: school?.levelColors?.[level],
  }));

  const classOptions = myClasses
    .map((c) => ({ id: c.id, name: c.name }))
    .sort((a, b) => a.name.localeCompare(b.name));

  return (
    <ClassDetail
      schoolClass={{ ...schoolClass, createdAt: schoolClass.createdAt.toISOString() }}
      levelOptions={levelOptions}
      classOptions={classOptions}
      levelsEnabled={levelsEnabled}
    />
  );
}
