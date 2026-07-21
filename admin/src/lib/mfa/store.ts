import "server-only";
import { getAdminDb } from "@/lib/firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { generateSecret, buildOtpauthUri, verifyTotp } from "./totp";
import {
  encryptSecret,
  decryptSecret,
  getMfaKey,
  type EncryptedSecret,
} from "./crypto";

// Server-only storage for the super-admin TOTP factor.
//
// Doc `adminMfa/{uid}` (deny-all in firestore.rules — only the admin runtime SA
// touches it):
//   { secret?: EncryptedSecret, enrolledAt, lastUsedAt, lastStep,
//     pending?: { secret: EncryptedSecret, createdAt } }
// `pending` holds the not-yet-confirmed secret during enrollment; the active
// `secret` only appears after a confirming code.

const ISSUER = "Lumi Admin";
const PENDING_TTL_MS = 15 * 60 * 1000;

interface MfaDoc {
  secret?: EncryptedSecret;
  lastStep?: number;
  pending?: { secret: EncryptedSecret; createdAt?: { toMillis?: () => number } };
}

function ref(uid: string) {
  return getAdminDb().collection("adminMfa").doc(uid);
}

// True once the active (confirmed) secret exists. A dangling `pending`-only doc
// does NOT count as enrolled.
export async function hasMfa(uid: string): Promise<boolean> {
  const snap = await ref(uid).get();
  return snap.exists && !!(snap.data() as MfaDoc).secret;
}

// Begin enrollment: mint a fresh secret, store it under `pending`, and return
// the provisioning material for the QR/secret display. Overwrites any prior
// pending secret (restarting enrollment is safe).
export async function startEnrollment(
  uid: string,
  accountName: string,
): Promise<{ secret: string; otpauthUri: string }> {
  const secret = generateSecret();
  const enc = encryptSecret(secret, getMfaKey());
  await ref(uid).set(
    { pending: { secret: enc, createdAt: FieldValue.serverTimestamp() } },
    { merge: true },
  );
  return {
    secret,
    otpauthUri: buildOtpauthUri({ secretBase32: secret, accountName, issuer: ISSUER }),
  };
}

// Confirm enrollment with a code against the pending secret. On success the
// pending secret becomes the active secret. Returns false on a bad/expired code.
export async function confirmEnrollment(
  uid: string,
  code: string,
  nowMs: number,
): Promise<boolean> {
  const snap = await ref(uid).get();
  const data = snap.data() as MfaDoc | undefined;
  const pending = data?.pending;
  if (!pending?.secret) return false;
  const createdMs = pending.createdAt?.toMillis?.() ?? 0;
  if (createdMs && nowMs - createdMs > PENDING_TTL_MS) return false;

  const secret = decryptSecret(pending.secret, getMfaKey());
  const result = verifyTotp(secret, code, { timeMs: nowMs });
  if (!result.ok) return false;

  await ref(uid).set(
    {
      secret: pending.secret,
      lastStep: result.step ?? null,
      enrolledAt: FieldValue.serverTimestamp(),
      lastUsedAt: FieldValue.serverTimestamp(),
      pending: FieldValue.delete(),
    },
    { merge: true },
  );
  return true;
}

// Verify a login code against the active secret, advancing lastStep so the same
// code can never be replayed. Returns false if not enrolled or the code is bad.
export async function verifyLogin(
  uid: string,
  code: string,
  nowMs: number,
): Promise<boolean> {
  const snap = await ref(uid).get();
  const data = snap.data() as MfaDoc | undefined;
  if (!data?.secret) return false;

  const secret = decryptSecret(data.secret, getMfaKey());
  const result = verifyTotp(secret, code, {
    timeMs: nowMs,
    lastStep: typeof data.lastStep === "number" ? data.lastStep : undefined,
  });
  if (!result.ok) return false;

  await ref(uid).set(
    { lastStep: result.step ?? null, lastUsedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  return true;
}

// Recovery: remove a super-admin's enrollment, forcing fresh enrollment on next
// login. Used by the audited portal peer-reset and the break-glass script.
export async function resetMfa(uid: string): Promise<void> {
  await ref(uid).delete();
}
