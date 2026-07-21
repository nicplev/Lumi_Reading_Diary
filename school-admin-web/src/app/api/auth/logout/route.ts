import { NextResponse } from 'next/server';
import { clearSession } from '@/lib/auth/session';
import { assertSameOrigin, RequestGuardError } from '@/lib/http/request-guards';

export async function POST(request: Request) {
  // This route took no body and no token, so any site could force-log-out a
  // signed-in user by POSTing to it. Impact is only nuisance, but the fix is
  // free. Safe to origin-check: the only callers are same-origin browser
  // fetches in auth-context.tsx — unlike /api/auth/session, nothing calls
  // this server-to-server.
  try {
    assertSameOrigin(request);
  } catch (error) {
    if (error instanceof RequestGuardError) {
      return NextResponse.json({ error: error.message }, { status: error.status });
    }
    throw error;
  }

  await clearSession();
  return NextResponse.json({ success: true });
}
