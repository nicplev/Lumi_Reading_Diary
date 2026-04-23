import { NextResponse } from 'next/server';
import {
  createSessionCookie,
  getSession,
  type SessionData,
} from '@/lib/auth/session';

// Ends an active impersonation session. The client is expected to call the
// `endImpersonationSession` Cloud Function (for audit) before hitting this
// endpoint — we only restore the server-side cookie here. If the client
// skipped that call, the scheduled `expireImpersonationSessions` function
// will still clean the Firestore session doc at its 30-min TTL.

export async function POST() {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  if (!session.impersonation) {
    return NextResponse.json(
      { error: 'No impersonation session is active.' },
      { status: 409 },
    );
  }

  const restored: SessionData = {
    uid: session.uid,
    email: session.email,
    fullName: session.fullName,
    schoolId: session.impersonation.realSchoolId,
    role: session.impersonation.realRole,
  };

  await createSessionCookie(restored);
  return NextResponse.json({ ok: true });
}
