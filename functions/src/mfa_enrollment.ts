/**
 * Server-side phone second-factor enrollment + signup finalisation.
 *
 * Identity Platform blocks MFA enrollment until the account's email is verified
 * — and this applies to the Admin SDK too, not just clients. Lumi enrolls phone
 * MFA during signup (before the user verifies their email), so the client links
 * the SMS-verified phone and calls this function, which:
 *   1. enrolls the phone as a second factor (temporarily marking the email
 *      verified just for the enroll, then restoring it so the app's
 *      email-verification gate still bites);
 *   2. unlinks the primary phone provider so the phone is a SECOND FACTOR ONLY;
 *   3. FINALISES the signup server-side — writes the parent/teacher doc, the
 *      userSchoolIndex entries, and (parent) links the student. This must be
 *      server-side because enrolling MFA bumps `tokensValidAfterTime`, which
 *      revokes the client's session — so the client can't write anything after
 *      the enroll;
 *   4. mints a custom token so the client can re-establish a session and land
 *      on home (or, if custom-token sign-in is MFA-challenged, route to login —
 *      the data is already finalised either way).
 *
 * Idempotent and retry-safe.
 */

import * as crypto from "crypto";
import * as admin from "firebase-admin";
import * as functions from "firebase-functions/v1";
import {linkParentToStudentCore, resolveLinkCodeSchool} from "./parent_linking";
import {resolveSchoolCode} from "./code_verification";

const fns = functions.region("australia-southeast1");

// App Check enforcement, opt-in via env var (default OFF). These callables fire
// during signup — before the account is fully set up — so enforcement must NOT
// be flipped on until the client attestation rollout is verified in the App
// Check console, else new signups break (1.6). App Check attests the APP, not
// the account, so an unverified-email/pre-finalise caller still attests fine.
const MFA_ENROLLMENT_APP_CHECK_ENFORCED =
  process.env.MFA_ENROLLMENT_APP_CHECK_ENFORCED === "true";

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

/** SHA-256 hex of [value]; mirrors UserSchoolIndexService in the app.
 * @param {string} value The pre-normalised key (lowercased email / E.164 phone).
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

/**
 * Upserts a userSchoolIndex entry (email- or phone-keyed) for fast login
 * school resolution. Doc id is sha256 of the normalised key.
 * @param {string} key Normalised key (lowercased email or E.164 phone).
 * @param {Record<string, unknown>} fields The index fields to write.
 * @return {Promise<void>} Resolves when written.
 */
async function upsertIndex(
  key: string,
  fields: Record<string, unknown>,
): Promise<void> {
  await admin
    .firestore()
    .collection("userSchoolIndex")
    .doc(sha256Hex(key))
    .set(
      {...fields, updatedAt: admin.firestore.FieldValue.serverTimestamp()},
      {merge: true},
    );
}

interface FinalizeContext {
  schoolId: string;
  fullName: string;
  email: string | null;
  phoneE164: string;
  relationshipLabel: string | null;
  linkCode: string | null;
}

/**
 * Parent signup finalisation: writes the parent doc (if new), the email/phone
 * indexes, and links the student via the shared link-core. All server-side, so
 * it survives the session revocation that enrolling MFA causes.
 * @param {string} uid The parent's UID.
 * @param {FinalizeContext} ctx The signup context.
 * @return {Promise<void>} Resolves when finalised.
 */
async function finalizeParent(
  uid: string,
  ctx: FinalizeContext,
): Promise<void> {
  const db = admin.firestore();
  const parentRef = db
    .collection("schools").doc(ctx.schoolId)
    .collection("parents").doc(uid);

  const snap = await parentRef.get();
  if (!snap.exists) {
    await parentRef.set({
      email: ctx.email,
      fullName: ctx.fullName,
      role: "parent",
      schoolId: ctx.schoolId,
      linkedChildren: [],
      classIds: [],
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      phoneNumber: ctx.phoneE164,
      phoneVerified: true,
      relationshipLabel: ctx.relationshipLabel,
    });
    try {
      await db.collection("schools").doc(ctx.schoolId).update({
        parentCount: admin.firestore.FieldValue.increment(1),
      });
    } catch (_) {
      // Non-critical counter.
    }
  } else if (ctx.relationshipLabel) {
    await parentRef.update({relationshipLabel: ctx.relationshipLabel});
  }

  if (ctx.email) {
    await upsertIndex(ctx.email.toLowerCase(), {
      email: ctx.email,
      schoolId: ctx.schoolId,
      userType: "parent",
      userId: uid,
    });
  }
  await upsertIndex(ctx.phoneE164, {
    phoneNumber: ctx.phoneE164,
    schoolId: ctx.schoolId,
    userType: "parent",
    userId: uid,
  });

  if (ctx.linkCode) {
    try {
      await linkParentToStudentCore(uid, ctx.linkCode.toUpperCase());
    } catch (err) {
      const kind = (err as {details?: {kind?: string}})?.details?.kind;
      if (kind !== "already-linked") {
        throw err; // invalid/used/revoked/expired code — surface to the client.
      }
    }
  }
}

/**
 * Teacher signup finalisation: writes the teacher user doc + email index.
 * @param {string} uid The teacher's UID.
 * @param {FinalizeContext} ctx The signup context.
 * @return {Promise<void>} Resolves when finalised.
 */
async function finalizeTeacher(
  uid: string,
  ctx: FinalizeContext,
): Promise<void> {
  const db = admin.firestore();
  await db
    .collection("schools").doc(ctx.schoolId)
    .collection("users").doc(uid)
    .set({
      email: ctx.email,
      fullName: ctx.fullName,
      role: "teacher",
      schoolId: ctx.schoolId,
      classIds: [],
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastLoginAt: admin.firestore.FieldValue.serverTimestamp(),
      phoneNumber: ctx.phoneE164,
      phoneVerified: true,
      permissions: {
        notifications: {
          assignedClasses: true,
          assignedStudents: true,
          schedule: true,
          wholeSchool: false,
        },
      },
    }, {merge: true});

  if (ctx.email) {
    await upsertIndex(ctx.email.toLowerCase(), {
      email: ctx.email,
      schoolId: ctx.schoolId,
      userType: "user",
      userId: uid,
    });
  }
  try {
    await db.collection("schools").doc(ctx.schoolId).update({
      teacherCount: admin.firestore.FieldValue.increment(1),
    });
  } catch (_) {
    // Non-critical counter.
  }
}

export const enrollLinkedPhoneAsMfa = fns
  .runWith({
    timeoutSeconds: 60,
    memory: "256MB",
    enforceAppCheck: MFA_ENROLLMENT_APP_CHECK_ENFORCED,
    consumeAppCheckToken: MFA_ENROLLMENT_APP_CHECK_ENFORCED,
  })
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

    // Optional signup-finalisation context. When `role` is present we finalise
    // the whole signup server-side (the client's session is dead after enroll).
    const role = data?.role === "parent" || data?.role === "teacher" ?
      data.role :
      null;
    // Derive the email from the VERIFIED auth token, never from client `data`.
    // Trusting data.email let a caller write an arbitrary email onto their
    // membership doc and, worse, poison userSchoolIndex/{sha256(email)} for an
    // address they don't own (hijacking that email's login school resolution).
    // The token email is the address this account actually authenticated with.
    const tokenEmail = optStr(
      (context.auth?.token as {email?: unknown} | undefined)?.email,
    );
    const linkCode = optStr(data?.linkCode);

    // Derive schoolId server-side from a validated JOIN CREDENTIAL, never from a
    // bare client `data.schoolId` (1.3). A teacher must present a valid school
    // code; a parent's school comes from their (valid) student link code. This
    // is the gate that stops an authenticated caller provisioning a membership
    // into an arbitrary school — the teacher case is the high-severity one
    // (school membership grants broad read access to the school's students).
    //
    // Transitional fallback: pre-1.3 clients that send only `data.schoolId`
    // keep working until the app adopts the credential fields AND the rules
    // deploy (1.3-rules) denies client self-create. Remove the fallback then.
    let derivedSchoolId: string | null = null;
    if (role === "teacher") {
      const schoolCode = optStr(data?.schoolCode);
      if (schoolCode) {
        // Read-only — the school code is NOT consumed, so this is retry-safe.
        derivedSchoolId = (await resolveSchoolCode(schoolCode)).schoolId;
      }
    } else if (role === "parent" && linkCode) {
      try {
        derivedSchoolId =
          (await resolveLinkCodeSchool(linkCode.toUpperCase())).schoolId;
      } catch (err) {
        // On a retry the link code is already "used" (we consumed it on the
        // first run), so re-resolution throws `code-used`. That's the idempotent
        // path — the parent doc and link already exist — so fall through to
        // data.schoolId (which equals the code's school for a real signup).
        // Any OTHER validity failure (invalid/revoked/expired) is fatal here,
        // before we touch MFA, so a bad code can't half-finalise a signup.
        const kind = (err as {details?: {kind?: string}})?.details?.kind;
        if (kind !== "code-used") throw err;
      }
    }

    const ctx: FinalizeContext | null = role ? {
      schoolId: derivedSchoolId ?? optStr(data?.schoolId) ?? "",
      fullName: optStr(data?.fullName) ?? "",
      email: tokenEmail ?? optStr(data?.email),
      phoneE164: rawPhone,
      relationshipLabel: optStr(data?.relationshipLabel),
      linkCode,
    } : null;
    if (role && (!ctx?.schoolId)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId is required when finalising signup.",
      );
    }

    const auth = admin.auth();

    // Require the linked phone as proof of ownership. Auth is read-after-write
    // consistent, but allow one short retry for propagation safety.
    let user: admin.auth.UserRecord;
    try {
      user = await auth.getUser(uid);
    } catch (err) {
      if ((err as {code?: string})?.code === "auth/user-not-found") {
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

    // ── Enroll as a second factor unless it already is (idempotent) ──────────
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

      // The verified-email rule applies to the Admin SDK too — mark the email
      // verified ONLY for the enroll, then restore it so the splash gate still
      // requires real verification.
      const restoreUnverified = user.emailVerified === false;
      if (restoreUnverified) {
        await auth.updateUser(uid, {emailVerified: true});
      }
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
      } finally {
        if (restoreUnverified) {
          try {
            await auth.updateUser(uid, {emailVerified: false});
          } catch (e) {
            functions.logger.error(
              "enrollLinkedPhoneAsMfa: failed to restore emailVerified=false",
              {uid, error: e instanceof Error ? e.message : String(e)},
            );
          }
        }
      }
    }

    // Phone becomes a SECOND FACTOR only — unlink the primary phone provider.
    try {
      await auth.updateUser(uid, {providersToUnlink: ["phone"]});
    } catch (err) {
      functions.logger.warn("enrollLinkedPhoneAsMfa unlink failed", {
        uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    // ── Finalise the signup server-side (the client's session is now dead) ───
    if (ctx) {
      if (role === "parent") {
        await finalizeParent(uid, ctx);
      } else {
        await finalizeTeacher(uid, ctx);
      }
    }

    // Mint a custom token so the client can re-establish a session (the enroll
    // revoked the old one) and reach home. Non-fatal if it fails — the client
    // falls back to the login screen, and the data is already finalised.
    let customToken: string | null = null;
    try {
      customToken = await auth.createCustomToken(uid);
    } catch (err) {
      functions.logger.error("enrollLinkedPhoneAsMfa custom token failed", {
        uid,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    return {enrolled: true, finalised: ctx !== null, customToken};
  });

// ─────────────────────────────────────────────────────────────────────────────
// Callable: finalizeParentSignup  (phone-PRIMARY parent — no MFA enroll)
// ─────────────────────────────────────────────────────────────────────────────
//
// The phone-primary parent signup path (parent_registration_modal.dart) signs
// in WITH the phone number as the primary credential — there is no MFA enroll,
// so the client session stays live and the client USED to write the parent doc
// + userSchoolIndex + child link itself. That client self-create is exactly
// what the 1.3 rules deploy removes. This callable performs the same
// finalisation server-side (Admin SDK), DERIVING schoolId from the presented
// link code so a caller can't mint a parent membership in an arbitrary school.
//
// Proof of ownership: the caller's token must carry `phone_number` equal to the
// finalised phone (they signed in with it). Idempotent — finalizeParent no-ops
// the doc write when it already exists and swallows an already-linked child.
interface FinalizeParentSignupInput {
  linkCode?: unknown;
  fullName?: unknown;
  phoneE164?: unknown;
  email?: unknown;
  relationshipLabel?: unknown;
  schoolId?: unknown; // transitional fallback only — see enroll derivation.
}

export const finalizeParentSignup = fns
  .runWith({
    timeoutSeconds: 60,
    memory: "256MB",
    enforceAppCheck: MFA_ENROLLMENT_APP_CHECK_ENFORCED,
    consumeAppCheckToken: MFA_ENROLLMENT_APP_CHECK_ENFORCED,
  })
  .https.onCall(async (data: FinalizeParentSignupInput, context) => {
    const uid = context.auth?.uid;
    if (!uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "You must be signed in to finalise signup.",
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
    // Proof of phone ownership: a phone-primary parent signed in WITH this
    // number, so the verified token must carry it. This stops a caller
    // finalising a parent doc under a phone they don't own.
    const tokenPhone = optStr(
      (context.auth?.token as {phone_number?: unknown} | undefined)
        ?.phone_number,
    );
    if (tokenPhone !== rawPhone) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Phone number does not match the signed-in account.",
      );
    }

    const linkCode = optStr(data?.linkCode);
    // Derive schoolId from the validated link code (1.3), with the same
    // retry-safe `code-used` fallthrough as the enroll path. Transitional
    // fallback to data.schoolId until the app adopts + the rules deploy lands.
    let derivedSchoolId: string | null = null;
    if (linkCode) {
      try {
        derivedSchoolId =
          (await resolveLinkCodeSchool(linkCode.toUpperCase())).schoolId;
      } catch (err) {
        const kind = (err as {details?: {kind?: string}})?.details?.kind;
        if (kind !== "code-used") throw err;
      }
    }

    // Phone-primary accounts have no verified email; keep the client-supplied
    // email (unchanged behaviour — this callable is a client→server MOVE, not an
    // email-verification change). Email-index trust is tracked separately.
    const tokenEmail = optStr(
      (context.auth?.token as {email?: unknown} | undefined)?.email,
    );
    const ctx: FinalizeContext = {
      schoolId: derivedSchoolId ?? optStr(data?.schoolId) ?? "",
      fullName: optStr(data?.fullName) ?? "",
      email: tokenEmail ?? optStr(data?.email),
      phoneE164: rawPhone,
      relationshipLabel: optStr(data?.relationshipLabel),
      linkCode,
    };
    if (!ctx.schoolId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "schoolId is required to finalise signup.",
      );
    }

    await finalizeParent(uid, ctx);
    return {finalised: true, schoolId: ctx.schoolId};
  });
