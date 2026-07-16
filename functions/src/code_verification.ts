import * as functions from "firebase-functions/v1";
import {onCall, CallableOptions} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {enforcePublicCodeRateLimit} from "./public_code_rate_limit";

const COLL_SCHOOL_CODES = "schoolCodes";

// App Check enforcement, opt-in via env var. Default off — this fires during
// teacher registration, before the account exists, so a half-rolled-out App
// Check would lock new teachers out. Flip via
// CODE_VERIFICATION_APP_CHECK_ENFORCED=true once attestation rollout is verified.
const APP_CHECK_ENFORCED =
  process.env.CODE_VERIFICATION_APP_CHECK_ENFORCED === "true";

function runtime(
  opts: Pick<CallableOptions, "timeoutSeconds" | "memory">
): CallableOptions {
  return {
    ...opts,
    enforceAppCheck: APP_CHECK_ENFORCED,
    consumeAppCheckToken: APP_CHECK_ENFORCED,
  };
}

function invalidArgument(kind: string, message: string) {
  return new functions.https.HttpsError("invalid-argument", message, {kind});
}

function failedPrecondition(kind: string, message: string) {
  return new functions.https.HttpsError("failed-precondition", message, {kind});
}

function notFound(kind: string, message: string) {
  return new functions.https.HttpsError("not-found", message, {kind});
}

function parseExpiresAt(raw: unknown): Date | null {
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw === "string") {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

export interface ResolvedSchoolCode {
  codeId: string;
  schoolId: string;
  schoolName: string;
  ref: FirebaseFirestore.DocumentReference;
}

export function assertSchoolCodeUsable(
  d: FirebaseFirestore.DocumentData,
  now = new Date(),
): void {
  if (d.isActive !== true) {
    throw failedPrecondition(
      "code_inactive",
      "This school code has been deactivated.",
    );
  }
  const expiresAt = parseExpiresAt(d.expiresAt);
  if (expiresAt !== null && expiresAt < now) {
    throw failedPrecondition("code_expired", "This school code has expired.");
  }
  const maxUsages = typeof d.maxUsages === "number" ? d.maxUsages : null;
  const usageCount = typeof d.usageCount === "number" ? d.usageCount : 0;
  if (maxUsages !== null && usageCount >= maxUsages) {
    throw failedPrecondition(
      "code_max_usage",
      "This school code has reached its maximum usage limit.",
    );
  }
}

// Resolves a school code by EXACT value and runs the validity ladder (mirrors
// SchoolCodeModel.isValid / invalidReason). Throws the same typed HttpsErrors
// (with `kind`) as `verifySchoolCode`. Read-only — never mutates the code doc.
//
// Shared by the `verifySchoolCode` callable (teacher app verifies at the start
// of registration) and server-side teacher signup finalisation
// (enrollLinkedPhoneAsMfa), so the school code is the entitlement credential the
// server DERIVES schoolId from — a caller can no longer provision themselves
// into an arbitrary school by passing a bare `schoolId`.
export async function resolveSchoolCode(
  rawCode: string
): Promise<ResolvedSchoolCode> {
  const normalized =
    (typeof rawCode === "string" ? rawCode : "").toUpperCase().trim();

  if (normalized.length === 0) {
    throw invalidArgument("empty_code", "School code cannot be empty.");
  }
  if (normalized.length < 6) {
    throw invalidArgument(
      "code_too_short",
      "School code must be at least 6 characters."
    );
  }

  const snap = await admin
    .firestore()
    .collection(COLL_SCHOOL_CODES)
    .where("code", "==", normalized)
    .limit(1)
    .get();

  if (snap.empty) {
    throw notFound(
      "code_not_found",
      "Invalid school code. Please check the code and try again."
    );
  }

  const doc = snap.docs[0];
  const d = doc.data() ?? {};

  assertSchoolCodeUsable(d);

  return {
    codeId: doc.id,
    schoolId: String(d.schoolId ?? ""),
    schoolName: String(d.schoolName ?? ""),
    ref: doc.ref,
  };
}

/**
 * Atomically consumes one teacher school-code use. A server-owned redemption
 * record makes retries by the same Auth UID idempotent while enforcing expiry
 * and max-usage limits for new accounts.
 * @param {string} rawCode Submitted school join code.
 * @param {string} uid Authenticated teacher UID consuming the code.
 * @return {Promise<ResolvedSchoolCode>} The server-derived school identity.
 */
export async function consumeSchoolCode(
  rawCode: string,
  uid: string,
): Promise<ResolvedSchoolCode> {
  const normalized = rawCode.toUpperCase().trim();
  if (!uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }
  if (normalized.length < 6 || normalized.length > 16) {
    throw invalidArgument("invalid_code", "School code format is invalid.");
  }

  const db = admin.firestore();
  const snap = await db.collection(COLL_SCHOOL_CODES)
    .where("code", "==", normalized).limit(1).get();
  if (snap.empty) {
    throw notFound(
      "code_not_found",
      "Invalid school code. Please check the code and try again.",
    );
  }

  const codeRef = snap.docs[0].ref;
  const redemptionId = crypto.createHash("sha256")
    .update(`${codeRef.id}:${uid}`).digest("hex");
  const redemptionRef = db.collection("schoolCodeRedemptions").doc(redemptionId);

  return db.runTransaction(async (tx) => {
    const [fresh, redemption] = await Promise.all([
      tx.get(codeRef),
      tx.get(redemptionRef),
    ]);
    const d = fresh.data() ?? {};
    if (String(d.code ?? "").toUpperCase() !== normalized) {
      throw notFound("code_not_found", "Invalid school code.");
    }

    const schoolId = String(d.schoolId ?? "");
    const schoolName = String(d.schoolName ?? "");
    if (!schoolId) {
      throw failedPrecondition("invalid_code", "School code is malformed.");
    }

    if (!redemption.exists) {
      assertSchoolCodeUsable(d);
      const usageCount = typeof d.usageCount === "number" ? d.usageCount : 0;
      const now = admin.firestore.Timestamp.now();
      tx.update(codeRef, {usageCount: usageCount + 1, lastUsedAt: now});
      tx.create(redemptionRef, {
        codeId: codeRef.id,
        uid,
        schoolId,
        redeemedAt: now,
        expiresAt: admin.firestore.Timestamp.fromMillis(
          now.toMillis() + 400 * 24 * 60 * 60 * 1000,
        ),
      });
    }

    return {codeId: codeRef.id, schoolId, schoolName, ref: codeRef};
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Callable: verifySchoolCode  (read-only, exact-code lookup)
// ─────────────────────────────────────────────────────────────────────────────
//
// Replaces the client-side `where('code','==',x)` query the Flutter app used to
// run against `schoolCodes` (which required an unauthenticated `list` rule that
// let anyone paginate and harvest every active school join code — feeding the
// self-provision-as-teacher attack). This callable looks a code up by EXACT
// value and returns only that school's id/name/codeId — no enumeration.
//
// Intentionally UNAUTHENTICATED: the teacher app verifies the school code at the
// start of registration, before the account exists (teacher_registration_
// modal.dart). Validity mirrors SchoolCodeModel.isValid / invalidReason exactly.
export const verifySchoolCode = onCall(
  runtime({timeoutSeconds: 15, memory: "256MiB"}),
  async (request) => {
    const data: {code?: unknown} = request.data;
    const raw = typeof data?.code === "string" ? data.code : "";
    await enforcePublicCodeRateLimit("school", request);
    const resolved = await resolveSchoolCode(raw);
    return {
      ok: true,
      schoolId: resolved.schoolId,
      schoolName: resolved.schoolName,
      codeId: resolved.codeId,
    };
  });
