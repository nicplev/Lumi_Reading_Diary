import 'server-only';

import { createHash } from 'node:crypto';
import { adminDb } from '@/lib/firebase/admin';

/**
 * Shared origin and rate-limit guards for portal API routes.
 *
 * These began life inside the demo-allocation module, which was the only
 * place in the portal with either control. They are lifted here so the auth
 * routes can reuse them rather than growing a second implementation —
 * duplicated security code drifts, and only one copy ever gets the fix.
 */
export class RequestGuardError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
    this.name = 'RequestGuardError';
  }
}

/** Stable hex digest. Used for rate-limit document ids and for pseudonymising
 *  actor ids in audit records. */
export function sha256(value: string): string {
  return createHash('sha256').update(value).digest('hex');
}

/** Best-effort client IP behind Firebase Hosting / Cloud Run. */
export function clientIp(request: Request): string {
  return request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
}

/**
 * Reject browser mutations unless their Origin resolves to this host.
 *
 * NOTE: this requires an `Origin` header, so it must NOT be applied to any
 * endpoint with legitimate server-to-server callers — see the auth session
 * route, which is called by the super-admin portal's demo preflight without
 * one.
 */
export function assertSameOrigin(request: Request): void {
  const origin = request.headers.get('origin');
  const fetchSite = request.headers.get('sec-fetch-site');
  const forwardedHost = request.headers.get('x-forwarded-host')?.split(',')[0]?.trim();
  const expectedHost = forwardedHost || request.headers.get('host') || new URL(request.url).host;
  const forwardedProtocol = request.headers.get('x-forwarded-proto')?.split(',')[0]?.trim();
  const expectedProtocol = `${forwardedProtocol || new URL(request.url).protocol.replace(':', '')}:`;

  if (!origin) throw new RequestGuardError('Missing request origin.', 403);
  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new RequestGuardError('Invalid request origin.', 403);
  }
  if (
    parsed.host !== expectedHost ||
    parsed.protocol !== expectedProtocol ||
    (fetchSite && fetchSite !== 'same-origin')
  ) {
    throw new RequestGuardError('Cross-origin request refused.', 403);
  }
}

export interface RateLimitRule {
  /** Unhashed identity for this window, e.g. `${uid}:login`. */
  key: string;
  max: number;
  windowMs: number;
}

/**
 * Fixed-window counters in `portalRateLimits`, one transaction for all rules.
 *
 * Throws `RequestGuardError(429)` when any rule is exhausted. A failure of the
 * limiter ITSELF is the caller's decision — see `consumeRateLimitSoft` for the
 * fail-open variant used on the login path, where a Firestore blip must not
 * lock every school out of the portal.
 */
export async function consumeRateLimit(
  namespace: string,
  rules: RateLimitRule[],
  message: string,
): Promise<void> {
  const now = new Date();
  const refs = rules.map((rule) =>
    adminDb.collection('portalRateLimits').doc(`${namespace}_${sha256(rule.key)}`),
  );

  await adminDb.runTransaction(async (tx) => {
    const snapshots = await tx.getAll(...refs);
    for (let index = 0; index < rules.length; index += 1) {
      const rule = rules[index];
      const data = snapshots[index].data();
      const resetAt = data?.resetAt?.toDate?.() as Date | undefined;
      const withinWindow = resetAt instanceof Date && resetAt > now;
      const count = withinWindow && typeof data?.count === 'number' ? data.count : 0;
      if (count >= rule.max) {
        throw new RequestGuardError(message, 429);
      }
      tx.set(refs[index], {
        count: count + 1,
        resetAt: withinWindow ? resetAt : new Date(now.getTime() + rule.windowMs),
        updatedAt: now,
      });
    }
  });
}

/**
 * As `consumeRateLimit`, but a failure of the limiter infrastructure is
 * swallowed rather than surfaced.
 *
 * Used on the login path deliberately: these limits exist to bound cost and
 * abuse, not to authenticate anyone. Letting a Firestore outage turn into
 * "nobody at any school can sign in" would trade a small abuse risk for a
 * total outage. A genuine 429 still propagates.
 */
export async function consumeRateLimitSoft(
  namespace: string,
  rules: RateLimitRule[],
  message: string,
): Promise<void> {
  try {
    await consumeRateLimit(namespace, rules, message);
  } catch (error) {
    if (error instanceof RequestGuardError) throw error;
    console.error(`rate limit unavailable for ${namespace}`, error);
  }
}
