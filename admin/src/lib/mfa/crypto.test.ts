import assert from "node:assert/strict";
import test from "node:test";

import { deriveKey, encryptSecret, decryptSecret } from "./crypto.ts";

const KEY = deriveKey("a-test-encryption-secret-at-least-32-chars-long!!");

test("encrypt/decrypt round-trips the secret", () => {
  const secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
  const enc = encryptSecret(secret, KEY);
  assert.notEqual(enc.ciphertext, secret);
  assert.ok(enc.iv && enc.tag && enc.ciphertext);
  assert.equal(decryptSecret(enc, KEY), secret);
});

test("each encryption uses a fresh IV (ciphertext differs)", () => {
  const a = encryptSecret("same-plaintext", KEY);
  const b = encryptSecret("same-plaintext", KEY);
  assert.notEqual(a.iv, b.iv);
  assert.notEqual(a.ciphertext, b.ciphertext);
});

test("tampered ciphertext fails the GCM auth tag", () => {
  const enc = encryptSecret("secret", KEY);
  const tampered = {
    ...enc,
    ciphertext: Buffer.from("ZZZZ" + enc.ciphertext).toString("base64"),
  };
  assert.throws(() => decryptSecret(tampered, KEY));
});

test("a wrong key fails to decrypt", () => {
  const enc = encryptSecret("secret", KEY);
  const wrong = deriveKey("a-different-secret-that-is-also-32-chars-plus!!");
  assert.throws(() => decryptSecret(enc, wrong));
});
