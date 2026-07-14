/**
 * Callable: resolveUserSchoolByUid
 *
 * Server-side replacement for the Flutter login fallback that iterates the
 * whole `schools` collection client-side to find a signed-in user whose email
 * is not yet in `userSchoolIndex` (see lib/screens/auth/login_screen.dart).
 *
 * That client `list` on /schools is the cross-tenant metadata-exposure surface
 * tracked as security finding #5: the `schools` list rule is currently open to
 * any signed-in user, so a collection query returns every school's address /
 * contact / subscription fields. This callable is the ENABLER for removing that
 * rule — once the app resolves an un-indexed user's school through here instead
 * of listing /schools, `allow list` on /schools can be set to `false`.
 *
 * For the authenticated caller it finds their staff (`users`) or `parents`
 * membership across all schools, backfills the email index so the fast path is
 * used next time, and returns the resolved school. It only writes the index —
 * it never mutates business data — and is scoped to the CALLER's own uid, so it
 * cannot be used to resolve anyone else's membership.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {onCall, CallableOptions} from "firebase-functions/v2/https";

// App Check enforcement, opt-in via env var. Default off — this fires on the
// login fallback path, and a half-rolled-out App Check would block legitimate
// logins. Flip via SCHOOL_RESOLUTION_APP_CHECK_ENFORCED=true once attestation
// rollout is verified.
const APP_CHECK_ENFORCED =
  process.env.SCHOOL_RESOLUTION_APP_CHECK_ENFORCED === "true";

function runtime(
  opts: Pick<CallableOptions, "timeoutSeconds" | "memory">
): CallableOptions {
  return {
    ...opts,
    enforceAppCheck: APP_CHECK_ENFORCED,
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

/**
 * SHA-256 hex of [value]; mirrors UserSchoolIndexService in the app.
 * @param {string} value The pre-normalised key (lowercased email).
 * @return {string} The hex digest used as the index doc id.
 */
function sha256Hex(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

/**
 * Optional trimmed string, or null.
 * @param {unknown} v The raw value.
 * @return {string|null} Trimmed non-empty string, else null.
 */
function optStr(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length === 0 ? null : t;
}

export const resolveUserSchoolByUid = onCall(
  runtime({timeoutSeconds: 30, memory: "256MiB"}),
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to resolve your school.",
      );
    }

    const db = admin.firestore();
    const tokenEmail = optStr(
      (request.auth?.token as {email?: unknown} | undefined)?.email,
    );

    // Find the caller's membership doc by uid. collectionGroup queries cannot
    // filter by leaf document id, so scan the (small) membership collections
    // and match on doc.id. This is a rare fallback — only when the email index
    // is missing — and it backfills the index below so it is not repeated for
    // this user. Switch to an indexed `where('email','==')` collection-group
    // query if membership volume grows large.
    for (const coll of ["users", "parents"] as const) {
      const snap = await db.collectionGroup(coll).get();
      const match = snap.docs.find((d) => d.id === uid);
      if (!match) continue;

      const schoolId = match.ref.parent.parent?.id;
      if (!schoolId) continue;

      const userType = coll === "parents" ? "parent" : "user";
      const email = tokenEmail ?? optStr(match.data().email);
      if (email) {
        await db
          .collection("userSchoolIndex")
          .doc(sha256Hex(email.toLowerCase()))
          .set(
            {
              email: email.toLowerCase(),
              schoolId,
              userType,
              userId: uid,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
          );
      }

      return {schoolId, userType, userId: uid};
    }

    throw new functions.https.HttpsError(
      "not-found",
      "No school membership was found for this account.",
    );
  },
);
