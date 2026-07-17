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
 * For the authenticated caller it reads a server-owned UID index, verifies the
 * authoritative membership and backfills the email index so the fast path is
 * used next time. A bounded query over the existing top-level email/phone index
 * supports accounts created before the UID index migration; membership
 * subcollections are never scanned.
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

    type Candidate = {schoolId: string; userType: "parent" | "user"};
    let candidate: Candidate | null = null;

    const uidIndex = await db.doc(`userMembershipIndex/${uid}`).get();
    const indexedSchoolId = optStr(uidIndex.data()?.schoolId);
    const indexedType = uidIndex.data()?.userType;
    if (
      uidIndex.exists &&
      indexedSchoolId &&
      (indexedType === "parent" || indexedType === "user")
    ) {
      candidate = {schoolId: indexedSchoolId, userType: indexedType};
    }

    if (!candidate) {
      // Migration-only compatibility path. This is an indexed, bounded query
      // over the small top-level lookup collection—not a collection-group scan.
      const legacyIndexes = await db
        .collection("userSchoolIndex")
        .where("userId", "==", uid)
        .limit(10)
        .get();
      const unique = new Map<string, Candidate>();
      for (const doc of legacyIndexes.docs) {
        const schoolId = optStr(doc.data().schoolId);
        const userType = doc.data().userType;
        if (
          schoolId &&
          (userType === "parent" || userType === "user")
        ) {
          unique.set(`${schoolId}:${userType}`, {schoolId, userType});
        }
      }
      if (unique.size === 1) candidate = [...unique.values()][0];
    }

    if (candidate) {
      const collection = candidate.userType === "parent" ? "parents" : "users";
      const membership = await db
        .doc(`schools/${candidate.schoolId}/${collection}/${uid}`)
        .get();
      if (membership.exists) {
        await db.doc(`userMembershipIndex/${uid}`).set({
          userId: uid,
          schoolId: candidate.schoolId,
          userType: candidate.userType,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const email = tokenEmail ?? optStr(membership.data()?.email);
        if (email) {
          await db
            .collection("userSchoolIndex")
            .doc(sha256Hex(email.toLowerCase()))
            .set(
              {
                email: email.toLowerCase(),
                schoolId: candidate.schoolId,
                userType: candidate.userType,
                userId: uid,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              {merge: true},
            );
        }

        return {...candidate, userId: uid};
      }

      // Remove a stale UID index only when it still points at this candidate.
      if (uidIndex.exists) {
        await db.runTransaction(async (transaction) => {
          const fresh = await transaction.get(uidIndex.ref);
          if (
            fresh.data()?.schoolId === candidate?.schoolId &&
            fresh.data()?.userType === candidate?.userType
          ) {
            transaction.delete(uidIndex.ref);
          }
        });
      }
    }

    throw new functions.https.HttpsError(
      "not-found",
      "No school membership was found for this account.",
    );
  },
);
