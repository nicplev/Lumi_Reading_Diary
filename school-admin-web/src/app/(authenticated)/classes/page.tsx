import { getSession } from '@/lib/auth/session';
import { redirect } from 'next/navigation';
import { getClasses, getTeachers } from '@/lib/firestore/classes';
import { ClassesPage } from './classes-page';

export default async function ClassesRoute() {
  const session = await getSession();
  if (!session) redirect('/login');

  const isAdmin = session.role === 'schoolAdmin';

  // Teachers go straight to their class detail (which hosts a switcher when they
  // have more than one), mirroring the app — no admin-style List/Board landing.
  if (!isAdmin) {
    const myClasses = await getClasses(session.schoolId, { teacherId: session.uid });
    if (myClasses.length > 0) {
      const first = [...myClasses].sort((a, b) => a.name.localeCompare(b.name))[0];
      redirect(`/classes/${first.id}`);
    }
    // No class assigned → ClassesPage renders a teacher empty state.
  }

  const teachers = await getTeachers(session.schoolId);
  return <ClassesPage teachers={teachers} isAdmin={isAdmin} />;
}
