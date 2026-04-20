import 'server-only';
import { createHash } from 'crypto';
import { adminDb } from '@/lib/firebase/admin';

// Dev access allowlist, stored in Firestore under /devAccessEmails/{sha256(email)}.
// The super-admin portal (lumi-admin) is the only writer. Here we only read.
//
// Looking up a specific email's access is a single keyed `get()` — no query —
// so per-request latency is bounded. Results are cached for the duration of
// the Node.js process (kept deliberately small: the list won't change often,
// and a stale deny/allow for a few seconds after a revoke is acceptable).

const COLLECTION = 'devAccessEmails';
const CACHE_TTL_MS = 30_000;

type CacheEntry = { value: boolean; expiresAt: number };
const cache = new Map<string, CacheEntry>();

function hashEmail(email: string): string {
  return createHash('sha256').update(email.trim().toLowerCase()).digest('hex');
}

export async function hasDevAccess(
  email: string | null | undefined,
): Promise<boolean> {
  if (!email) return false;
  const normalized = email.trim().toLowerCase();
  if (!normalized) return false;

  const now = Date.now();
  const cached = cache.get(normalized);
  if (cached && cached.expiresAt > now) return cached.value;

  const snap = await adminDb
    .collection(COLLECTION)
    .doc(hashEmail(normalized))
    .get();
  const value = snap.exists;
  cache.set(normalized, { value, expiresAt: now + CACHE_TTL_MS });
  return value;
}

// Exported for tests / admin tooling that needs to bypass the cache.
export function invalidateDevAccessCache(email?: string | null) {
  if (!email) {
    cache.clear();
    return;
  }
  cache.delete(email.trim().toLowerCase());
}
