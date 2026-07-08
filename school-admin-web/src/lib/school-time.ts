/**
 * School-timezone day/week math for server-side queries.
 *
 * The pure date math lives in `time-core.ts` (dependency-free so it can be
 * unit-run with plain Node); this module re-exports it and adds the cached
 * Firestore timezone lookup. Server code should import from here.
 */

import { adminDb } from '@/lib/firebase/admin';
import { DEFAULT_TIMEZONE } from './time-core';

export * from './time-core';

const tzCache = new Map<string, { tz: string; fetchedAt: number }>();
const TZ_CACHE_MS = 5 * 60 * 1000;

/** The school's IANA timezone, cached per server instance for 5 minutes. */
export async function getSchoolTimezone(schoolId: string): Promise<string> {
  const hit = tzCache.get(schoolId);
  if (hit && Date.now() - hit.fetchedAt < TZ_CACHE_MS) return hit.tz;
  let tz = DEFAULT_TIMEZONE;
  try {
    const snap = await adminDb.collection('schools').doc(schoolId).get();
    const raw = snap.data()?.timezone;
    if (typeof raw === 'string' && raw.length > 0) tz = raw;
  } catch {
    // Fall through to the default — a tz lookup must never break a dashboard.
  }
  tzCache.set(schoolId, { tz, fetchedAt: Date.now() });
  return tz;
}
