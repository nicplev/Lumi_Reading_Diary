// RFC 6238 TOTP / RFC 4226 HOTP for the super-admin second factor.
//
// Pure, dependency-free (node:crypto only) so it can be unit-tested against the
// published RFC vectors. Google Authenticator / most apps use HMAC-SHA1, 6
// digits, 30s period — that is what buildOtpauthUri advertises and what verify
// checks. No "server-only" here so `node --test` can import it directly; it is
// still only referenced by server code.

import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";

export const TOTP_STEP_SECONDS = 30;
export const TOTP_DIGITS = 6;

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

// RFC 4648 base32, no padding, uppercase — the authenticator-app convention.
export function base32Encode(buf: Buffer): string {
  let bits = 0;
  let value = 0;
  let out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) {
    out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
  }
  return out;
}

export function base32Decode(input: string): Buffer {
  const clean = input.replace(/=+$/, "").replace(/\s+/g, "").toUpperCase();
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    const idx = BASE32_ALPHABET.indexOf(ch);
    if (idx === -1) throw new Error("invalid base32 character");
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

// A fresh base32 TOTP secret (default 20 random bytes = 160 bits, RFC-recommended).
export function generateSecret(bytes = 20): string {
  return base32Encode(randomBytes(bytes));
}

// RFC 4226 HOTP: HMAC-SHA1 of the 8-byte big-endian counter, dynamic truncation.
export function hotp(secretBase32: string, counter: number, digits = TOTP_DIGITS): string {
  const key = base32Decode(secretBase32);
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const hmac = createHmac("sha1", key).update(buf).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const bin =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);
  return (bin % 10 ** digits).toString().padStart(digits, "0");
}

// The TOTP step (counter) for a wall-clock time in milliseconds.
export function currentStep(timeMs: number): number {
  return Math.floor(timeMs / 1000 / TOTP_STEP_SECONDS);
}

export function totp(secretBase32: string, timeMs: number, digits = TOTP_DIGITS): string {
  return hotp(secretBase32, currentStep(timeMs), digits);
}

function constantTimeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ba.length !== bb.length) return false;
  return timingSafeEqual(ba, bb);
}

export interface VerifyResult {
  ok: boolean;
  // The absolute step the code matched — persist it as lastStep so the same
  // code (or an earlier one) can never be replayed.
  step?: number;
}

// Verifies a 6-digit code within ±window steps of now. A candidate step at or
// below `lastStep` is refused (replay guard). Constant-time digit comparison.
export function verifyTotp(
  secretBase32: string,
  code: string,
  opts: { timeMs: number; window?: number; lastStep?: number },
): VerifyResult {
  const window = opts.window ?? 1;
  const normalized = (code ?? "").trim();
  if (!/^\d{6}$/.test(normalized)) return { ok: false };
  const step = currentStep(opts.timeMs);
  for (let i = -window; i <= window; i++) {
    const candidateStep = step + i;
    if (candidateStep < 0) continue;
    if (opts.lastStep !== undefined && candidateStep <= opts.lastStep) continue;
    if (constantTimeEqual(hotp(secretBase32, candidateStep), normalized)) {
      return { ok: true, step: candidateStep };
    }
  }
  return { ok: false };
}

// otpauth:// URI for the QR code the authenticator app scans.
export function buildOtpauthUri(params: {
  secretBase32: string;
  accountName: string;
  issuer: string;
}): string {
  // Per the otpauth spec the "issuer:account" colon is the label delimiter and
  // stays literal; the two halves are percent-encoded individually.
  const label =
    `${encodeURIComponent(params.issuer)}:${encodeURIComponent(params.accountName)}`;
  const query = new URLSearchParams({
    secret: params.secretBase32,
    issuer: params.issuer,
    algorithm: "SHA1",
    digits: String(TOTP_DIGITS),
    period: String(TOTP_STEP_SECONDS),
  });
  return `otpauth://totp/${label}?${query.toString()}`;
}
