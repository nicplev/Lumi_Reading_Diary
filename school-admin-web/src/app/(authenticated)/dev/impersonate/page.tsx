import { redirect } from 'next/navigation';
import { getSession } from '@/lib/auth/session';
import { hasDevAccess } from '@/lib/auth/dev-access';
import { ImpersonationPicker } from './impersonation-picker';

// Server-side gate: requires a signed-in user with developer access. All
// interactive state lives in the client component below.
export default async function ImpersonatePage() {
  const session = await getSession();
  if (!session) redirect('/login');
  if (!(await hasDevAccess(session.email))) redirect('/dashboard');
  if (session.impersonation) redirect('/dashboard');

  return <ImpersonationPicker />;
}
