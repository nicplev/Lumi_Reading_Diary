import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getCurrentAcademicYear, isSchoolSubActive } from '@/lib/access';
import { getRenewalRoster } from '@/lib/firestore/renewals';
import { RenewalsPage } from './renewals-page';

export default async function RenewalsRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const currentYear = await getCurrentAcademicYear();
  const targetYear = currentYear + 1;
  const [roster, subActive] = await Promise.all([
    getRenewalRoster(session.schoolId, targetYear),
    isSchoolSubActive(session.schoolId, targetYear),
  ]);

  return (
    <RenewalsPage
      currentYear={currentYear}
      targetYear={targetYear}
      subActive={subActive}
      initialRoster={roster}
    />
  );
}
