import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {HttpsError} from "firebase-functions/v2/https";

const COLLECTION = "publicCodeVerificationRateLimits";
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const MAX_PER_HOUR = 30;
const MAX_PER_DAY = 100;
const UNKNOWN_IP_MAX_PER_HOUR = 5;

type PublicCodeRequest = {
  rawRequest: {ip?: string};
  auth?: {uid: string};
};

type CounterData = {
  hourStart?: admin.firestore.Timestamp;
  hourCount?: number;
  dayStart?: admin.firestore.Timestamp;
  dayCount?: number;
};

export type NextPublicCodeCounter = {
  hourStartMs: number;
  hourCount: number;
  dayStartMs: number;
  dayCount: number;
};

/**
 * Advances a durable public-code counter, throwing before either ceiling.
 * Kept pure so boundary/reset behaviour has deterministic unit coverage.
 * @param {CounterData} previous Previously persisted counter values.
 * @param {number} nowMs Trusted server time in milliseconds.
 * @param {number} hourLimit Caller-specific hourly limit.
 * @return {NextPublicCodeCounter} The next counter state to persist.
 */
export function nextPublicCodeCounter(
  previous: CounterData,
  nowMs: number,
  hourLimit = MAX_PER_HOUR,
): NextPublicCodeCounter {
  let hourStartMs = previous.hourStart?.toMillis() ?? 0;
  let hourCount =
    typeof previous.hourCount === "number" ? previous.hourCount : 0;
  let dayStartMs = previous.dayStart?.toMillis() ?? 0;
  let dayCount = typeof previous.dayCount === "number" ? previous.dayCount : 0;

  if (!previous.hourStart || nowMs - hourStartMs >= HOUR_MS) {
    hourStartMs = nowMs;
    hourCount = 0;
  }
  if (!previous.dayStart || nowMs - dayStartMs >= DAY_MS) {
    dayStartMs = nowMs;
    dayCount = 0;
  }

  if (hourCount >= hourLimit || dayCount >= MAX_PER_DAY) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many code checks. Please wait before trying again.",
    );
  }

  return {
    hourStartMs,
    hourCount: hourCount + 1,
    dayStartMs,
    dayCount: dayCount + 1,
  };
}

function keyFor(kind: string, dimension: string): string {
  return crypto
    .createHash("sha256")
    .update(`${kind}:${dimension}`)
    .digest("hex");
}

/**
 * Applies durable per-IP and, when available, per-account limits before an
 * unauthenticated code lookup. Raw IPs and submitted codes are never stored.
 * @param {"school"|"student"} kind Code namespace being checked.
 * @param {PublicCodeRequest} request Callable request metadata.
 */
export async function enforcePublicCodeRateLimit(
  kind: "school" | "student",
  request: PublicCodeRequest,
): Promise<void> {
  const rawIp = request.rawRequest.ip?.trim();
  const ip = rawIp && rawIp.length <= 100 ? rawIp : "unknown";
  const dimensions = [`ip:${ip}`];
  if (request.auth?.uid) dimensions.push(`uid:${request.auth.uid}`);

  const db = admin.firestore();
  const refs = dimensions.map((dimension) =>
    db.collection(COLLECTION).doc(keyFor(kind, dimension)),
  );

  await db.runTransaction(async (tx) => {
    const snapshots = [];
    for (const ref of refs) snapshots.push(await tx.get(ref));
    const now = admin.firestore.Timestamp.now();
    const nowMs = now.toMillis();

    for (let i = 0; i < refs.length; i++) {
      const next = nextPublicCodeCounter(
        (snapshots[i].data() ?? {}) as CounterData,
        nowMs,
        ip === "unknown" && i === 0 ? UNKNOWN_IP_MAX_PER_HOUR : MAX_PER_HOUR,
      );
      tx.set(refs[i], {
        kind,
        hourStart: admin.firestore.Timestamp.fromMillis(next.hourStartMs),
        hourCount: next.hourCount,
        dayStart: admin.firestore.Timestamp.fromMillis(next.dayStartMs),
        dayCount: next.dayCount,
        updatedAt: now,
        expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + DAY_MS * 2),
      });
    }
  });
}
