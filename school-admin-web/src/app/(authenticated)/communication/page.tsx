import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { CommunicationPage } from './communication-page';

export default async function CommunicationRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  // Sending is gated off during a read-only dev impersonation session.
  return <CommunicationPage readOnly={!!session.impersonation} />;
}
