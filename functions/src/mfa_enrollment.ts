/**
 * Server-side phone second-factor enrollment.
 *
 * Identity Platform blocks CLIENT-side MFA enrollment until the account's
 * email is verified. Lumi enrolls phone MFA during signup — before the user
 * clicks the email verification link — so client enrollment fails with
 * `unverified-email` ("Need to verify email first before enrolling second
 * factors").
 *
 * Instead, the client verifies the phone via SMS and LINKS it to the account
 * (proving ownership), then calls this function. The Admin SDK is NOT subject
 * to the verified-email rule, so it can enroll the second factor. We then
 * unlink the primary phone provider so the phone is a SECOND FACTOR ONLY,
 * never a primary sign-in method. The email-verification gate elsewhere in the
 * app is unaffected.
 *
 * Idempotent and retry-safe: re-running with an already-enrolled phone skips
 * the enroll and just ensures the provider is unlinked.
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const fns = functions.region("australia-southeast1");

const E164_REGEX = /^\+[1-9]\d{7,14}$/;

/**
 * True when [user] has a linked `phone` provider matching [phoneE164] — the
 * proof of ownership the client establishes via linkWithCredential before
 * calling this function.
 * @param {admin.auth.UserRecord} user The Auth user record.
 * @param {string} phoneE164 The E.164 phone number to match.
 * @return {boolean} Whether the phone provider is linked.
 */
function hasLinkedPhone(
  user: admin.auth.UserRecord,
  phoneE164: string,
): boolean {
  return user.providerData.some(
    (p) => p.providerId === "phone" && p.phoneNumber === phoneE164,
  );
}

export const enrollLinkedPhoneAsMfa = fns
  .runWith({timeoutSeconds: 20, memory: "128MB"})
  .https.onCall(async (data, context) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to enroll a second factor.",
      );
    }

    const rawPhone =
      typeof data?.phoneE164 === "string" ? data.phoneE164.trim() : "";
    if (!E164_REGEX.test(rawPhone)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "phoneE164 must be in E.164 format (e.g. +61400000000).",
      );
    }
    const displayName =
      typeof data?.displayName === "string" && data.displayName.trim() ?
        data.displayName.trim().slice(0, 64) :
        rawPhone;

    const auth = admin.auth();

    // Require the linked phone as proof of ownership. Auth is read-after-write
    // consistent, but allow one short retry for propagation safety.
    let user: admin.auth.UserRecord;
    try {
      user = await auth.getUser(uid);
    } catch (err) {
      if ((err as {code?: string})?.code === "auth/user-not-found") {
        // The signed-in account no longer exists (e.g. deleted server-side
        // while the client still held a valid token). Surface clearly rather
        // than as a generic INTERNAL.
        throw new functions.https.HttpsError(
          "unauthenticated",
          "Your session is no longer valid. Please sign in again.",
        );
      }
      throw err;
    }
    if (!hasLinkedPhone(user, rawPhone)) {
      await new Promise((resolve) => setTimeout(resolve, 500));
      user = await auth.getUser(uid);
    }
    if (!hasLinkedPhone(user, rawPhone)) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Phone number is not verified for this account.",
      );
    }

    // Enroll as a second factor unless it already is (idempotent). At signup
    // there are no existing factors; preserve any that exist just in case.
    const existingFactors = user.multiFactor?.enrolledFactors ?? [];
    const alreadyEnrolled = existingFactors.some(
      (f) =>
        f.factorId === "phone" &&
        (f as admin.auth.PhoneMultiFactorInfo).phoneNumber === rawPhone,
    );

    if (!alreadyEnrolled) {
      const preserved = existingFactors.map((f) => ({
        uid: f.uid,
        phoneNumber: (f as admin.auth.PhoneMultiFactorInfo).phoneNumber,
        displayName: f.displayName ?? undefined,
        factorId: "phone" as const,
      }));
      try {
        await auth.updateUser(uid, {
          multiFactor: {
            enrolledFactors: [
              ...preserved,
              {phoneNumber: rawPhone, displayName, factorId: "phone"},
            ],
          },
        });
      } catch (err) {
        const code = (err as {code?: string})?.code ?? "";
        if (
          code.includes("second-factor-already-in-use") ||
          code.includes("already-exists")
        ) {
          throw new functions.https.HttpsError(
            "already-exists",
            "This phone number is already set up as a second factor on " +
              "another account.",
          );
        }
        functions.logger.error("enrollLinkedPhoneAsMfa enroll failed", {
          uid,
          code,
          error: err instanceof Error ? err.message : String(err),
        });
        throw new functions.https.HttpsError(
          "internal",
          "Could not enroll the phone as a second factor.",
        );
      }
    }

    // Remove the primary phone provider so phone is a SECOND FACTOR only.
    // Unlinking the provider does NOT remove the enrolled MFA factor (they are
    // stored separately). Non-fatal if it fails — a retry will clean it up.
    try {
      await auth.updateUser(uid, {providersToUnlink: ["phone"]});
    } catch (err) {
      functions.logger.warn("enrollLinkedPhoneAsMfa unlink failed", {
        uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    return {enrolled: true};
  });
