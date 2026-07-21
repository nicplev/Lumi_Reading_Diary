import assert from 'node:assert/strict';
import test from 'node:test';

import {
  allowVerifiedJwtAfterMembershipLookupFailure,
  isCurrentMembershipValid,
  isDefinitiveAuthLookupFailure,
  isSessionValidForAuthAccount,
  remainingSessionSeconds,
} from './session-policy.ts';

/** 2026-07-21T00:00:00Z */
const AUTH_TIME = 1784592000;
const iso = (epochSeconds: number) => new Date(epochSeconds * 1000).toISOString();

test('old session is rejected after deactivation, deletion or role change', () => {
  assert.equal(isCurrentMembershipValid(false, undefined, 'teacher'), false);
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher', isActive: false }, 'teacher'),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(
      true,
      { role: 'teacher', pendingDeletion: true },
      'teacher',
    ),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher' }, 'schoolAdmin'),
    false,
  );
  assert.equal(
    isCurrentMembershipValid(true, { role: 'teacher', isActive: true }, 'teacher'),
    true,
  );
});

test('membership lookup errors fail closed for mutable routes', () => {
  assert.equal(allowVerifiedJwtAfterMembershipLookupFailure(true), false);
  assert.equal(allowVerifiedJwtAfterMembershipLookupFailure(false), true);
});

test('revoking tokens ends the session', () => {
  // The whole point: a password reset or revokeRefreshTokens() moves
  // tokensValidAfterTime past the cookie's sign-in time. Before this check a
  // stolen cookie survived both for up to 5 days.
  assert.equal(
    isSessionValidForAuthAccount(
      { tokensValidAfterTime: iso(AUTH_TIME + 1) },
      AUTH_TIME,
    ),
    false,
  );
});

test('a session predating the revocation boundary is honoured', () => {
  assert.equal(
    isSessionValidForAuthAccount(
      { tokensValidAfterTime: iso(AUTH_TIME - 3600) },
      AUTH_TIME,
    ),
    true,
  );
  // Same second is honoured, matching admin/src/lib/auth.ts's comparison.
  assert.equal(
    isSessionValidForAuthAccount({ tokensValidAfterTime: iso(AUTH_TIME) }, AUTH_TIME),
    true,
  );
});

test('a disabled account is rejected regardless of timing', () => {
  assert.equal(
    isSessionValidForAuthAccount(
      { disabled: true, tokensValidAfterTime: iso(AUTH_TIME - 3600) },
      AUTH_TIME,
    ),
    false,
  );
  // ...including legacy cookies that carry no authTime at all.
  assert.equal(isSessionValidForAuthAccount({ disabled: true }, undefined), false);
});

test('legacy cookies without authTime skip the revocation comparison', () => {
  // Deliberate migration behaviour. Firebase defaults tokensValidAfterTime to
  // account-creation time, so treating a missing authTime as 0 would reject
  // every pre-existing cookie at once — logging out every teacher and forcing
  // every admin back through TOTP on deploy. These age out within 5 days.
  assert.equal(
    isSessionValidForAuthAccount({ tokensValidAfterTime: iso(AUTH_TIME + 1) }, undefined),
    true,
  );
});

test('unusable account state never silently grants access', () => {
  assert.equal(isSessionValidForAuthAccount(undefined, AUTH_TIME), false);
});

test('a re-mint keeps the original expiry instead of restarting the clock', () => {
  const now = AUTH_TIME;
  const fresh = 60 * 60 * 24 * 5;
  // Two days into a five-day session, editing your profile used to hand you a
  // brand new five days. It should leave three.
  const threeDays = 60 * 60 * 24 * 3;
  assert.equal(remainingSessionSeconds(now + threeDays, fresh, now), threeDays);
});

test('a first mint gets the full fresh window', () => {
  const fresh = 60 * 60 * 24 * 5;
  assert.equal(remainingSessionSeconds(undefined, fresh, AUTH_TIME), fresh);
  // Legacy cookies carry no expiresAt and must not be truncated to zero.
  assert.equal(remainingSessionSeconds(NaN, fresh, AUTH_TIME), fresh);
});

test('an already-expired session yields no cookie life', () => {
  assert.equal(remainingSessionSeconds(AUTH_TIME - 1, 999, AUTH_TIME), 0);
  assert.equal(remainingSessionSeconds(AUTH_TIME, 999, AUTH_TIME), 0);
});

test('a deleted account is definitive, not a transient outage', () => {
  // getUser() throws for BOTH a deleted account and a Firebase outage, and the
  // outage path fails open for reads. Conflating them would leave a deleted
  // user's cookie working — and impersonation/demo sessions skip the Firestore
  // membership check that would otherwise have caught it.
  assert.equal(isDefinitiveAuthLookupFailure({ code: 'auth/user-not-found' }), true);
  assert.equal(isDefinitiveAuthLookupFailure({ code: 'auth/internal-error' }), false);
  assert.equal(isDefinitiveAuthLookupFailure(new Error('socket hang up')), false);
  assert.equal(isDefinitiveAuthLookupFailure(undefined), false);
  assert.equal(isDefinitiveAuthLookupFailure(null), false);
});

test('a malformed or absent tokensValidAfterTime does not lock users out', () => {
  // An unparseable value must not become an accidental mass logout; the
  // membership check and cookie expiry still bound the session.
  assert.equal(isSessionValidForAuthAccount({}, AUTH_TIME), true);
  assert.equal(
    isSessionValidForAuthAccount({ tokensValidAfterTime: 'not-a-date' }, AUTH_TIME),
    true,
  );
  assert.equal(
    isSessionValidForAuthAccount({ tokensValidAfterTime: 12345 }, AUTH_TIME),
    true,
  );
});
