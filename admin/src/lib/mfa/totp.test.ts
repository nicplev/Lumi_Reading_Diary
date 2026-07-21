import assert from "node:assert/strict";
import test from "node:test";

import {
  base32Encode,
  base32Decode,
  hotp,
  totp,
  currentStep,
  verifyTotp,
  generateSecret,
  buildOtpauthUri,
  TOTP_STEP_SECONDS,
} from "./totp.ts";

// RFC 4226 Appendix D seed: ASCII "12345678901234567890".
const RFC_SECRET = base32Encode(Buffer.from("12345678901234567890"));

test("base32 encodes the RFC seed to the canonical value and round-trips", () => {
  assert.equal(RFC_SECRET, "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
  for (let i = 0; i < 50; i++) {
    const buf = Buffer.from([i, (i * 7) & 0xff, (i * 31) & 0xff, i ^ 0xa5]);
    assert.deepEqual(base32Decode(base32Encode(buf)), buf);
  }
});

test("hotp matches the RFC 4226 Appendix D 6-digit test vectors", () => {
  const expected = [
    "755224", "287082", "359152", "969429", "338314",
    "254676", "287922", "162583", "399871", "520489",
  ];
  expected.forEach((code, counter) => {
    assert.equal(hotp(RFC_SECRET, counter), code, `counter ${counter}`);
  });
});

test("totp derives the counter from the clock", () => {
  // At t = 59s the step is 1, so totp == hotp(secret, 1).
  const timeMs = 59 * 1000;
  assert.equal(currentStep(timeMs), 1);
  assert.equal(totp(RFC_SECRET, timeMs), hotp(RFC_SECRET, 1));
});

test("verifyTotp accepts the current code and honours the ± window", () => {
  const now = 100000 * 1000;
  const step = currentStep(now);
  const code = hotp(RFC_SECRET, step);
  const res = verifyTotp(RFC_SECRET, code, { timeMs: now });
  assert.equal(res.ok, true);
  assert.equal(res.step, step);

  // A code from one step ago is accepted (clock skew) within the default window.
  const prev = hotp(RFC_SECRET, step - 1);
  assert.equal(verifyTotp(RFC_SECRET, prev, { timeMs: now }).ok, true);

  // Two steps away is outside the default window.
  const old = hotp(RFC_SECRET, step - 2);
  assert.equal(verifyTotp(RFC_SECRET, old, { timeMs: now }).ok, false);
});

test("verifyTotp rejects replay: a code at or below lastStep is refused", () => {
  const now = 100000 * 1000;
  const step = currentStep(now);
  const code = hotp(RFC_SECRET, step);
  // Same code again with lastStep already at `step` must fail (replay).
  assert.equal(verifyTotp(RFC_SECRET, code, { timeMs: now, lastStep: step }).ok, false);
  // But a genuinely newer step still passes.
  const next = hotp(RFC_SECRET, step + 1);
  const res = verifyTotp(RFC_SECRET, next, { timeMs: now + TOTP_STEP_SECONDS * 1000, lastStep: step });
  assert.equal(res.ok, true);
  assert.equal(res.step, step + 1);
});

test("verifyTotp rejects malformed codes", () => {
  const now = Date.parse("2026-01-01T00:00:00Z");
  for (const bad of ["", "12345", "1234567", "abcdef", "12 456", "  "]) {
    assert.equal(verifyTotp(RFC_SECRET, bad, { timeMs: now }).ok, false);
  }
});

test("generateSecret produces a decodable base32 secret", () => {
  const secret = generateSecret();
  assert.match(secret, /^[A-Z2-7]+$/);
  assert.equal(base32Decode(secret).length, 20);
});

test("buildOtpauthUri encodes issuer, account and parameters", () => {
  const uri = buildOtpauthUri({
    secretBase32: RFC_SECRET,
    accountName: "admin@lumi.example",
    issuer: "Lumi Admin",
  });
  assert.ok(uri.startsWith("otpauth://totp/Lumi%20Admin:admin%40lumi.example?"));
  assert.ok(uri.includes(`secret=${RFC_SECRET}`));
  assert.ok(uri.includes("issuer=Lumi+Admin"));
  assert.ok(uri.includes(`period=${TOTP_STEP_SECONDS}`));
  assert.ok(uri.includes("digits=6"));
});
