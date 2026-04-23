import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { adminDb } from '@/lib/firebase/admin';
import { hasDevAccess } from '@/lib/auth/dev-access';
import {
  createSessionCookie,
  getSession,
  type SessionData,
} from '@/lib/auth/session';

// Client has already called the `startImpersonationSession` Cloud Function
// from the browser (with Firebase client SDK auth) and received a sessionId.
// This endpoint verifies the resulting Firestore session doc belongs to the
// caller and rewrites the JWT cookie so that every downstream API route and
// server component naturally queries the impersonated school.

const bodySchema = z.object({
  sessionId: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Gate: caller must hold developer access.
  if (!(await hasDevAccess(session.email))) {
    return NextResponse.json(
      { error: 'Developer access is required.' },
      { status: 403 },
    );
  }

  // Refuse if already impersonating — avoids accidental nested swap.
  if (session.impersonation) {
    return NextResponse.json(
      { error: 'An impersonation session is already active.' },
      { status: 409 },
    );
  }

  let parsed;
  try {
    parsed = bodySchema.parse(await request.json());
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 });
  }
  const { sessionId } = parsed;

  // Read the impersonation session doc and verify ownership + state.
  const snap = await adminDb
    .collection('devImpersonationSessions')
    .doc(sessionId)
    .get();
  if (!snap.exists) {
    return NextResponse.json({ error: 'Session not found.' }, { status: 404 });
  }
  const sd = snap.data() ?? {};
  if (sd.devUid !== session.uid) {
    return NextResponse.json(
      { error: 'This impersonation session belongs to a different user.' },
      { status: 403 },
    );
  }
  if (sd.status !== 'active') {
    return NextResponse.json(
      { error: `Session is ${sd.status}, not active.` },
      { status: 409 },
    );
  }

  const expiresAtMs =
    sd.expiresAt?.toMillis?.() ??
    (typeof sd.expiresAt === 'number' ? sd.expiresAt : null);
  const startedAtMs =
    sd.startedAt?.toMillis?.() ??
    (typeof sd.startedAt === 'number' ? sd.startedAt : Date.now());
  if (!expiresAtMs || expiresAtMs < Date.now()) {
    return NextResponse.json({ error: 'Session expired.' }, { status: 410 });
  }

  const targetSchoolId = String(sd.targetSchoolId ?? '');
  const targetUserId = String(sd.targetUserId ?? '');
  const targetRole = sd.targetRole as 'teacher' | 'schoolAdmin' | undefined;
  const schoolName = String(sd.targetSchoolName ?? '');
  const reason = String(sd.reason ?? '');
  if (!targetSchoolId || !targetUserId || !targetRole) {
    return NextResponse.json(
      { error: 'Session document is missing required fields.' },
      { status: 500 },
    );
  }

  const newSession: SessionData = {
    uid: session.uid,
    email: session.email,
    fullName: session.fullName,
    // EFFECTIVE school/role — every existing API route reads `session.schoolId`
    // and naturally queries the target school from this point on.
    schoolId: targetSchoolId,
    role: targetRole,
    impersonation: {
      sessionId,
      targetUserId,
      schoolName,
      reason,
      startedAt: startedAtMs,
      expiresAt: expiresAtMs,
      realSchoolId: session.schoolId,
      realRole: session.role,
    },
  };

  await createSessionCookie(newSession);
  return NextResponse.json({ ok: true });
}
