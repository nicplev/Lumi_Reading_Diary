import * as functions from "firebase-functions/v1";

/**
 * Refuses to proceed when the caller is inside a read-only developer
 * impersonation session.
 *
 * Impersonation mints a custom token carrying `devReadOnly: true`. Firestore
 * security rules already block direct client writes for such a token, but
 * Cloud Functions run with the Admin SDK and bypass those rules entirely — so
 * without this check a dev in a "read-only" session could still mutate data by
 * invoking a write callable. This is the callable-layer ("third") read-only
 * enforcement; call it at the top of every mutating callable.
 *
 * Safe to call unconditionally: a normal (non-impersonating) user never
 * carries the `devReadOnly` claim, so the guard is a no-op for them.
 *
 * Accepts a structural `{auth?: {token?}}` shape so it works with BOTH the v1
 * `CallableContext` and the v2 `CallableRequest` (whose `.auth?.token` has the
 * same meaning) — this lets callables migrate to Gen2 without touching every
 * call site (Phase 6).
 *
 * @param {object} ctx the callable context/request whose auth token is
 *   inspected for the `devReadOnly` claim (structural `{auth?: {token?}}`).
 * @return {void}
 */
export function assertNotReadOnly(
  ctx: {auth?: {token?: unknown} | null}
): void {
  const token = ctx.auth?.token as Record<string, unknown> | undefined;
  if (token?.devReadOnly === true) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "This action is blocked during a read-only impersonation session."
    );
  }
}
