export type PortalRole = 'teacher' | 'schoolAdmin';

export interface CurrentMembership {
  isActive?: unknown;
  pendingDeletion?: unknown;
  role?: unknown;
}

export function isCurrentMembershipValid(
  exists: boolean,
  membership: CurrentMembership | undefined,
  cookieRole: PortalRole,
): boolean {
  return (
    exists &&
    membership?.isActive !== false &&
    membership?.pendingDeletion !== true &&
    membership?.role === cookieRole
  );
}

export function allowVerifiedJwtAfterMembershipLookupFailure(
  requireMutable: boolean,
): boolean {
  return !requireMutable;
}

/**
 * Seconds of cookie life remaining for a re-minted session.
 *
 * `createSessionCookie` is called on every profile edit and on both ends of an
 * impersonation round trip, and it used to mint a fresh window each time — so
 * changing your display name silently extended your session by 5 days. When
 * the session already carries an absolute `expiresAt`, honour it instead of
 * starting a new window.
 *
 * Returns 0 when the session has already expired, which the caller treats as
 * "do not issue a cookie". In practice `getSession()` rejects an expired
 * cookie long before any re-mint, so this is a guard, not a live path.
 */
export function remainingSessionSeconds(
  expiresAt: number | undefined,
  freshWindowSeconds: number,
  nowSeconds: number,
): number {
  if (typeof expiresAt !== 'number' || !Number.isFinite(expiresAt)) {
    return freshWindowSeconds;
  }
  return Math.max(0, Math.floor(expiresAt - nowSeconds));
}

/**
 * True when an Auth lookup failure is a definitive "this account is gone",
 * not a transient outage.
 *
 * This distinction is load-bearing. `getUser()` throws for BOTH a deleted
 * account and a Firebase outage, and the outage path deliberately fails open
 * for reads. Without separating them, deleting a user would leave their
 * existing cookie working for reads until it expired — and impersonation and
 * demo sessions skip the Firestore membership check that would otherwise
 * have caught it.
 */
export function isDefinitiveAuthLookupFailure(error: unknown): boolean {
  const code = (error as { code?: unknown } | null | undefined)?.code;
  return code === 'auth/user-not-found';
}

export interface CurrentAuthAccount {
  disabled?: unknown;
  /** ISO string from the Admin SDK; set whenever tokens are revoked, the
   *  password changes, or the account is created. */
  tokensValidAfterTime?: unknown;
}

/**
 * Decides whether a verified `__session` cookie is still honoured given the
 * live Firebase Auth account state.
 *
 * WHY THIS EXISTS: the cookie is a locally-verified JWT, so revoking refresh
 * tokens does not touch it. Before this check, a stolen cookie outlived a
 * password reset by up to 5 days — and the 18 July incident response
 * ("revoked every refresh token") logged nobody out of this portal. The
 * super-admin portal has always done this; see admin/src/lib/auth.ts.
 *
 * `cookieAuthTime` is undefined for cookies minted before this shipped.
 * Those skip the revocation comparison rather than being rejected: Firebase
 * defaults `tokensValidAfterTime` to account-creation time, so treating a
 * missing value as 0 would log out every existing user at once and force
 * every admin back through TOTP. Legacy cookies still get the `disabled`
 * check, and age out within 5 days.
 */
export function isSessionValidForAuthAccount(
  account: CurrentAuthAccount | undefined,
  cookieAuthTime: number | undefined,
): boolean {
  if (!account) return false;
  if (account.disabled === true) return false;
  if (typeof cookieAuthTime !== 'number' || !Number.isFinite(cookieAuthTime)) {
    return true;
  }
  if (typeof account.tokensValidAfterTime !== 'string') return true;
  const validAfterMs = new Date(account.tokensValidAfterTime).getTime();
  if (Number.isNaN(validAfterMs)) return true;
  // Strictly greater: a token issued in the same second as the revocation
  // boundary is honoured, matching the super-admin portal's comparison.
  return Math.floor(validAfterMs / 1000) <= cookieAuthTime;
}
