import 'server-only';

import { FieldValue } from 'firebase-admin/firestore';
import { getSession, type SessionData } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import {
  assertSameOrigin,
  clientIp,
  consumeRateLimit,
  RequestGuardError,
  sha256,
} from '@/lib/http/request-guards';
import {
  hasDemoAllocationCapability,
  isCurrentDemoAllocationAuthority,
} from './allocation-policy';

/**
 * Extends the shared guard error so the demo routes' `instanceof
 * RequestGuardError` checks catch both this and anything thrown by the
 * shared origin/rate-limit helpers.
 */
export class DemoAllocationSecurityError extends RequestGuardError {
  constructor(message: string, status: number) {
    super(message, status);
    this.name = 'DemoAllocationSecurityError';
  }
}

export { assertSameOrigin };

export interface AuthorizedDemoAllocationSession {
  session: SessionData;
  generationId: string;
}

// Same windows and same `demo_alloc_` document namespace as before, so
// in-flight counters carry over unchanged.
async function consumeLimits(
  session: SessionData,
  operation: string,
  request: Request,
): Promise<void> {
  const ip = clientIp(request);
  await consumeRateLimit(
    'demo_alloc',
    [
      { key: `${session.uid}:${operation}`, max: 15, windowMs: 60_000 },
      { key: `${session.schoolId}:all`, max: 120, windowMs: 60 * 60_000 },
      { key: `${session.schoolId}:${ip}`, max: 60, windowMs: 60 * 60_000 },
    ],
    'Too many demo changes. Please wait and try again.',
  );
}

/**
 * Authorize the narrow demo-allocation exception. This deliberately does not
 * use `getSession({ requireMutable: true })`: the normal portal stays read-only
 * and only these dedicated handlers accept this independently re-verified
 * capability.
 */
export async function authorizeDemoAllocationMutation(
  request: Request,
  operation: string,
): Promise<AuthorizedDemoAllocationSession> {
  assertSameOrigin(request);
  const session = await getSession();
  if (!hasDemoAllocationCapability(session)) {
    throw new DemoAllocationSecurityError('Unauthorized.', 401);
  }

  const schoolRef = adminDb.collection('schools').doc(session.schoolId);
  const [school, membership, reseed] = await Promise.all([
    schoolRef.get(),
    schoolRef.collection('users').doc(session.uid).get(),
    adminDb.collection('demoAccess').doc('reseedStatus').get(),
  ]);
  const generationId = reseed.data()?.leaseId;
  const membershipData = membership.data();
  const current = isCurrentDemoAllocationAuthority({
    schoolExists: school.exists,
    schoolIsDemo: school.data()?.isDemo,
    membershipExists: membership.exists,
    membershipRole: membershipData?.role,
    membershipActive: membershipData?.isActive,
    membershipPendingDeletion: membershipData?.pendingDeletion,
    reseedState: reseed.data()?.state,
    reseedSchoolId: reseed.data()?.schoolId,
    reseedLeaseId: generationId,
    sessionSchoolId: session.schoolId,
    sessionGenerationId: session.demoGenerationId,
  });

  if (!current) {
    throw new DemoAllocationSecurityError(
      'This demo was refreshed. Sign out, sign in with today\'s credentials, and try again.',
      409,
    );
  }

  await consumeLimits(session, operation, request);
  return { session, generationId: generationId as string };
}

/** Audit only the event shape and a one-way actor id; never titles or names. */
export async function auditDemoAllocationMutation(
  session: SessionData,
  operation: string,
  outcome: 'succeeded' | 'rejected',
): Promise<void> {
  await adminDb.collection('demoAccessAudit').add({
    event: 'demo_allocation_mutation',
    operation,
    outcome,
    schoolId: session.schoolId,
    actorHash: sha256(session.uid),
    createdAt: FieldValue.serverTimestamp(),
  });
}
