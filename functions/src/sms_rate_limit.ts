/**
 * Per-phone-number SMS rate limit gate.
 *
 * The client SMS verification path calls this before invoking
 * `verifyPhoneNumber`. The gate enforces a daily cap per E.164 phone
 * number so a buggy retry loop or a malicious client can't burn the
 * project-wide SMS quota in a few seconds. Firebase's built-in 60-second
 * resend timeout is the only other guard.
 *
 * Configurable via `/platformConfig/smsRateLimits` (super-admin tunable):
 *  - enabled: boolean — when false the gate fails open (no enforcement).
 *    Defaults to false so deploying this code alone is a no-op.
 *  - maxPerDay: number — per-phone-number cap inside a rolling 24h window.
 *    Defaults to 5; generous for normal use (signup is 1 SMS, MFA is 1).
 */

import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

const RATE_LIMIT_CONFIG_DOC = "platformConfig/smsRateLimits";
const DEFAULT_MAX_PER_DAY = 5;
const WINDOW_MS = 24 * 60 * 60 * 1000;
const ALLOWED_PURPOSES = ["enrollment", "login", "primary"];

const E164_REGEX = /^\+[1-9]\d{7,14}$/;

interface RateLimitConfig {
  enabled: boolean;
  maxPerDay: number;
}

/**
 * Reads the super-admin tunable rate-limit config. Defaults `enabled` to
 * false so deploying the function before super-admin opt-in is a no-op.
 * @return {Promise<RateLimitConfig>} The current config.
 */
async function readConfig(): Promise<RateLimitConfig> {
  const snap = await admin.firestore().doc(RATE_LIMIT_CONFIG_DOC).get();
  const data = snap.data() ?? {};
  const rawCap = data.maxPerDay;
  const maxPerDay =
    typeof rawCap === "number" && Number.isFinite(rawCap) && rawCap > 0 ?
      Math.floor(rawCap) :
      DEFAULT_MAX_PER_DAY;
  return {
    enabled: data.enabled === true,
    maxPerDay,
  };
}

/**
 * Validates and normalizes the phone number from the callable payload.
 * @param {unknown} raw The phoneE164 input from the call.
 * @return {string} The normalized E.164 phone string.
 */
function normalizePhone(raw: unknown): string {
  if (typeof raw !== "string") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "phoneE164 must be a string in E.164 format (e.g. +14155551234).",
    );
  }
  const trimmed = raw.trim();
  if (!E164_REGEX.test(trimmed)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "phoneE164 must be in E.164 format (e.g. +14155551234).",
    );
  }
  return trimmed;
}

/**
 * Firestore document IDs can include '+' but it's safer to encode the
 * phone number for path-safety. The encoding is reversible and unique.
 * @param {string} phoneE164 The validated E.164 phone number.
 * @return {string} The encoded doc ID.
 */
function phoneToDocId(phoneE164: string): string {
  return encodeURIComponent(phoneE164);
}

export const requestSmsVerification = functions
  .runWith({timeoutSeconds: 15, memory: "128MB"})
  .https.onCall(async (data, context) => {
    const phone = normalizePhone(data?.phoneE164);
    const purpose = typeof data?.purpose === "string" ? data.purpose : "";
    if (!ALLOWED_PURPOSES.includes(purpose)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        `purpose must be one of: ${ALLOWED_PURPOSES.join(", ")}.`,
      );
    }

    const config = await readConfig();
    if (!config.enabled) {
      // Gate is opted-out (the default). Fail open — don't block users
      // while the rollout is still in monitoring mode.
      return {ok: true, remainingToday: -1, gateEnabled: false};
    }

    const db = admin.firestore();
    const docRef = db.collection("smsRateLimits").doc(phoneToDocId(phone));

    let allowed = false;
    let remainingToday = 0;

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(docRef);
        const existing = snap.data() ?? {};
        const windowStart = existing.windowStart as
          | admin.firestore.Timestamp
          | undefined;
        const existingCount =
          typeof existing.count === "number" ? existing.count : 0;

        const now = admin.firestore.Timestamp.now();
        const inWindow = windowStart ?
          now.toMillis() - windowStart.toMillis() < WINDOW_MS :
          false;

        const currentCount = inWindow ? existingCount : 0;

        if (currentCount >= config.maxPerDay) {
          allowed = false;
          remainingToday = 0;
          return;
        }

        const newCount = currentCount + 1;
        tx.set(docRef, {
          count: newCount,
          windowStart: inWindow && windowStart ? windowStart : now,
          lastSentAt: now,
          lastPurpose: purpose,
          lastCaller: context.auth?.uid ?? null,
        });

        allowed = true;
        remainingToday = Math.max(0, config.maxPerDay - newCount);
      });
    } catch (err) {
      functions.logger.error("requestSmsVerification transaction failed", {
        phoneTail: phone.slice(-4),
        error: err instanceof Error ? err.message : String(err),
      });
      // Internal error in our own code shouldn't lock the user out — fall
      // through and let the SMS attempt go through. If this becomes a
      // pattern, flip the policy to closed.
      return {ok: true, remainingToday: -1, gateEnabled: true, fallthrough: true};
    }

    if (!allowed) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Too many verification codes sent to this number recently. " +
          "Please try again in 24 hours.",
      );
    }

    return {ok: true, remainingToday, gateEnabled: true};
  });
