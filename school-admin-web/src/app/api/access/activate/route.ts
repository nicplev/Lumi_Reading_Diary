import { NextResponse } from 'next/server';
import { getSession } from '@/lib/auth/session';
import { getCurrentAcademicYear } from '@/lib/access';
import {
  activateAccessForYear,
  SubscriptionInactiveError,
} from '@/lib/firestore/access-activation';

// POST /api/access/activate — grant reading access to every active student
// who doesn't have live access yet, for the current academic year. The
// self-serve replacement for the backfill-access ops script.
export async function POST() {
  const session = await getSession({ requireMutable: true });
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  if (session.role !== 'schoolAdmin') {
    return NextResponse.json(
      { error: 'Only school admins can activate access' },
      { status: 403 }
    );
  }

  try {
    const year = await getCurrentAcademicYear();
    const result = await activateAccessForYear(session.schoolId, year, session.uid);
    return NextResponse.json(result);
  } catch (error) {
    if (error instanceof SubscriptionInactiveError) {
      return NextResponse.json({ error: error.message }, { status: 409 });
    }
    console.error('Access activation error:', error);
    return NextResponse.json({ error: 'Failed to activate access' }, { status: 500 });
  }
}
