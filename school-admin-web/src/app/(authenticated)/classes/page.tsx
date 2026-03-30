import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getTeachers } from '@/lib/firestore/classes';
import { ClassesPage } from './classes-page';

export default async function ClassesRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const teachers = await getTeachers(session.schoolId);

  return <ClassesPage teachers={teachers} />;
}
