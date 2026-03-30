import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { UsersPage } from './users-page';

export default async function UsersRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  return <UsersPage />;
}
