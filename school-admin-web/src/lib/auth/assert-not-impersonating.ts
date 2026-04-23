import 'server-only';
import { NextResponse } from 'next/server';
import { isImpersonating, type SessionData } from './session';

/**
 * Defence-in-depth guard for API mutation routes. The middleware already
 * blocks non-GET methods globally when `session.impersonation` is set, but
 * calling this at the top of a mutation handler means the block still holds
 * if the middleware is ever bypassed (e.g. a direct server-action invocation,
 * or a future middleware refactor).
 *
 * Returns a ready-to-return Response when the request should be rejected,
 * or `null` when the request is allowed to proceed.
 *
 * Usage:
 *   const blocked = assertNotImpersonating(session);
 *   if (blocked) return blocked;
 */
export function assertNotImpersonating(session: SessionData | null): NextResponse | null {
  if (!session) return null;
  if (!isImpersonating(session)) return null;
  return NextResponse.json(
    {
      error:
        'Impersonation is read-only. Exit the session to perform this action.',
      code: 'impersonation_read_only',
    },
    { status: 403 },
  );
}
