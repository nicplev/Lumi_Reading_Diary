import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClass } from '@/lib/firestore/classes';
import { getSchool } from '@/lib/firestore/school';
import { getReadingLevels } from '@/lib/types';
import { ClassDetail } from './class-detail';
import type { ReadingLevelOption } from '@/lib/types';

export default async function ClassDetailRoute({ params }: { params: Promise<{ classId: string }> }) {
  const session = await getSession();
  if (!session) redirect('/login');

  const { classId } = await params;
  const [schoolClass, school] = await Promise.all([
    getClass(session.schoolId, classId),
    getSchool(session.schoolId),
  ]);

  if (!schoolClass) redirect('/classes');

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
    <ClassDetail
      schoolClass={{ ...schoolClass, createdAt: schoolClass.createdAt.toISOString() }}
      levelOptions={levelOptions}
    />
  );
}
