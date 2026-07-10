import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClasses } from '@/lib/firestore/classes';
import { getCurrentAcademicYear, isRenewalWindowOpen, isSchoolSubActive } from '@/lib/access';
import { getRecentRolloverImports } from '@/lib/firestore/rollover';
import { getRecentRenewalBatches, getRenewalRoster } from '@/lib/firestore/renewals';
import { RolloverWizard } from './rollover-wizard';

export default async function RolloverRoute() {
  const session = await getSession();
  if (!session) redirect('/login');
  if (session.role !== 'schoolAdmin') redirect('/students');

  const currentAcademicYear = await getCurrentAcademicYear();
  const targetAcademicYear = currentAcademicYear + 1;
  const [classes, recentImports, renewalRoster, renewalSubActive, recentRenewalBatches] = await Promise.all([
    getClasses(session.schoolId),
    getRecentRolloverImports(session.schoolId),
    getRenewalRoster(session.schoolId, targetAcademicYear),
    isSchoolSubActive(session.schoolId, targetAcademicYear),
    getRecentRenewalBatches(session.schoolId),
  ]);

  return (
    <RolloverWizard
      classes={classes.map((c) => ({ id: c.id, name: c.name, yearLevel: c.yearLevel ?? null }))}
      currentAcademicYear={currentAcademicYear}
      targetAcademicYear={targetAcademicYear}
      recentImports={recentImports}
      initialRenewalRoster={renewalRoster}
      renewalSubActive={renewalSubActive}
      renewalWindowOpen={isRenewalWindowOpen(targetAcademicYear)}
      recentRenewalBatches={recentRenewalBatches}
    />
  );
}
