import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClasses } from '@/lib/firestore/classes';
import { getSchool } from '@/lib/firestore/school';
import { getReadingLevels } from '@/lib/types';
import { StudentsPage } from './students-page';
import type { ReadingLevelOption } from '@/lib/types';

export default async function StudentsRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const [classes, school] = await Promise.all([
    getClasses(session.schoolId, {
      teacherId: session.role === 'teacher' ? session.uid : undefined,
    }),
    getSchool(session.schoolId),
  ]);

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
    <StudentsPage
      classes={classes.map((c) => ({ ...c, createdAt: c.createdAt.toISOString() }))}
      levelOptions={levelOptions}
    />
  );
}
