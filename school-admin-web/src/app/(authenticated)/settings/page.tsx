import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { SettingsPage } from './settings-page';

export default async function SettingsRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  return <SettingsPage />;
}
