import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { SettingsPage } from './settings-page';
import { getCurrentAcademicYear, isSchoolSubActive, isRenewalWindowOpen } from '@/lib/access';
import { getRenewalRoster } from '@/lib/firestore/renewals';

export default async function SettingsRoute({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string }>;
}) {
  const session = await getSession();
  if (!session) redirect('/login');

  const { tab } = await searchParams;

  // Renewals is an admin-only Settings tab (a once-a-year tool). Pre-load its
  // roster server-side for admins so the tab renders instantly — the data is
  // small (one school's active students).
  let renewals = null;
  if (session.role === 'schoolAdmin') {
    const currentYear = await getCurrentAcademicYear();
    const targetYear = currentYear + 1;
    const [roster, subActive] = await Promise.all([
      getRenewalRoster(session.schoolId, targetYear),
      isSchoolSubActive(session.schoolId, targetYear),
    ]);
    renewals = {
      currentYear,
      targetYear,
      subActive,
      windowOpen: isRenewalWindowOpen(targetYear),
      roster,
    };
  }

  return <SettingsPage initialTab={tab} renewals={renewals} />;
}
