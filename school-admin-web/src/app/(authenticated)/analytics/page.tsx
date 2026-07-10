import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getSchool } from '@/lib/firestore/school';
import { AnalyticsPage } from './analytics-page';

export default async function AnalyticsRoute() {
  const session = await getSession();
  if (!session) redirect('/login');
  // Admin-only (matches the sidebar's adminOnly flag): the data is
  // whole-school, and a year-period load scans the school's entire log
  // history — neither should be reachable by a teacher session.
  if (session.role !== 'schoolAdmin') redirect('/dashboard');

  const school = await getSchool(session.schoolId);

  // Serialize termDates (Dates → ISO strings) for the client component
  const termDates = Object.fromEntries(
    Object.entries(school?.termDates ?? {}).map(([k, v]) => [k, v instanceof Date ? v.toISOString() : String(v)])
  );

  return (
    <AnalyticsPage
      levelSchema={school?.levelSchema ?? 'none'}
      termDates={termDates}
    />
  );
}
