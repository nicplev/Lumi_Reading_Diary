import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getSchool } from '@/lib/firestore/school';
import { getReadingLevels } from '@/lib/types';
import { LibraryPage } from './library-page';
import type { ReadingLevelOption } from '@/lib/types';

export default async function LibraryRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const school = await getSchool(session.schoolId);
  const levels = getReadingLevels(school?.levelSchema ?? 'aToZ', school?.customLevels);
  const levelOptions: ReadingLevelOption[] = levels.map((level, i) => ({
    value: level,
    shortLabel: level,
    displayLabel: level,
    sortIndex: i,
    schema: school?.levelSchema ?? 'aToZ',
    colorHex: school?.levelColors?.[level],
  }));

  return <LibraryPage levelOptions={levelOptions} />;
}
