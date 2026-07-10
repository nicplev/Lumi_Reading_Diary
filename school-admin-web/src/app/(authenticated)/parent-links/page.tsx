import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { ParentLinksPage } from './parent-links-page';

export default async function ParentLinksRoute() {
  const session = await getSession();
  if (!session) redirect('/login');
  if (session.role !== 'schoolAdmin') redirect('/dashboard');

  return <ParentLinksPage />;
}
