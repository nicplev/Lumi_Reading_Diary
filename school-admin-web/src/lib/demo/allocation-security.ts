import 'server-only';

import { createHash } from 'node:crypto';
import { FieldValue } from 'firebase-admin/firestore';
import { getSession, type SessionData } from '@/lib/auth/session';
import { adminDb } from '@/lib/firebase/admin';
import {
  hasDemoAllocationCapability,
  isCurrentDemoAllocationAuthority,
} from './allocation-policy';

export class DemoAllocationSecurityError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'DemoAllocationSecurityError';
  }
}

export interface AuthorizedDemoAllocationSession {
  session: SessionData;
  generationId: string;
}

function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

/** Reject browser mutations unless their Origin resolves to this host. */
export function assertSameOrigin(request: Request): void {
  const origin = request.headers.get('origin');
  const fetchSite = request.headers.get('sec-fetch-site');
  const forwardedHost = request.headers.get('x-forwarded-host')?.split(',')[0]?.trim();
  const expectedHost = forwardedHost || request.headers.get('host') || new URL(request.url).host;
  const forwardedProtocol = request.headers.get('x-forwarded-proto')?.split(',')[0]?.trim();
  const expectedProtocol = `${forwardedProtocol || new URL(request.url).protocol.replace(':', '')}:`;

  if (!origin) throw new DemoAllocationSecurityError('Missing request origin.', 403);
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new DemoAllocationSecurityError('Invalid request origin.', 403);
  }
  if (
    parsed.host !== expectedHost ||
    parsed.protocol !== expectedProtocol ||
    (fetchSite && fetchSite !== 'same-origin')
  ) {
    throw new DemoAllocationSecurityError('Cross-origin request refused.', 403);
  }
}

async function consumeLimits(
  session: SessionData,
  operation: string,
  request: Request,
): Promise<void> {
  const now = new Date();
  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  const limits = [
    { key: `${session.uid}:${operation}`, max: 15, windowMs: 60_000 },
    { key: `${session.schoolId}:all`, max: 120, windowMs: 60 * 60_000 },
    { key: `${session.schoolId}:${ip}`, max: 60, windowMs: 60 * 60_000 },
  ];
  const refs = limits.map((limit) =>
    adminDb.collection('portalRateLimits').doc(`demo_alloc_${sha256(limit.key)}`),
  );

  await adminDb.runTransaction(async (tx) => {
    const snapshots = await tx.getAll(...refs);
    for (let index = 0; index < limits.length; index += 1) {
      const limit = limits[index];
      const ref = refs[index];
      const data = snapshots[index].data();
      const resetAt = data?.resetAt?.toDate?.() as Date | undefined;
      const withinWindow = resetAt instanceof Date && resetAt > now;
      const count = withinWindow && typeof data?.count === 'number' ? data.count : 0;
      if (count >= limit.max) {
        throw new DemoAllocationSecurityError('Too many demo changes. Please wait and try again.', 429);
      }
      tx.set(ref, {
        count: count + 1,
        resetAt: withinWindow ? resetAt : new Date(now.getTime() + limit.windowMs),
        updatedAt: now,
      });
    }
  });
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
