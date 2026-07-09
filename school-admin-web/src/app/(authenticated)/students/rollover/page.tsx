import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClasses } from '@/lib/firestore/classes';
import { getCurrentAcademicYear } from '@/lib/access';
import { getRecentRolloverImports } from '@/lib/firestore/rollover';
import { RolloverWizard } from './rollover-wizard';

export default async function RolloverRoute() {
  const session = await getSession();
  if (!session) redirect('/login');
  if (session.role !== 'schoolAdmin') redirect('/students');

  const [classes, currentAcademicYear, recentImports] = await Promise.all([
    getClasses(session.schoolId),
    getCurrentAcademicYear(),
    getRecentRolloverImports(session.schoolId),
  ]);

  return (
    <RolloverWizard
      classes={classes.map((c) => ({ id: c.id, name: c.name, yearLevel: c.yearLevel ?? null }))}
      currentAcademicYear={currentAcademicYear}
      recentImports={recentImports}
    />
  );
}
