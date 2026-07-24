// AES-256-GCM encryption for the stored TOTP secret.
//
// The TOTP secret must be recoverable server-side to verify codes, so it is
// encrypted at rest in a deny-all Firestore doc (never in plaintext). The key
// comes from the ADMIN_MFA_ENC_KEY_AU secret (Secret Manager, AU replica),
// normalised to 32 bytes via SHA-256. encrypt/decrypt take an explicit key so
// they are unit-testable without the environment.

import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";

export interface EncryptedSecret {
  ciphertext: string; // base64
  iv: string; // base64 (12 bytes)
  tag: string; // base64 (16 bytes)
}

// Derive a 32-byte key from the raw secret string. The secret is already
// high-entropy random; SHA-256 just normalises its length for AES-256.
export function deriveKey(rawSecret: string): Buffer {
  return createHash("sha256").update(rawSecret, "utf8").digest();
}

export function getMfaKey(): Buffer {
  const raw = process.env.ADMIN_MFA_ENC_KEY_AU;
  if (!raw || raw.length < 32) {
    throw new Error("ADMIN_MFA_ENC_KEY_AU must contain at least 32 characters");
  }
  return deriveKey(raw);
}

export function encryptSecret(plaintext: string, key: Buffer): EncryptedSecret {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv, { authTagLength: 16 });
  const ciphertext = Buffer.concat([cipher.update(plaintext, "utf8"), cipher.final()]);
  return {
    ciphertext: ciphertext.toString("base64"),
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
  };
}

// Throws if the ciphertext or tag has been tampered with (GCM auth failure).
export function decryptSecret(enc: EncryptedSecret, key: Buffer): string {
  const tag = Buffer.from(enc.tag, "base64");
  // GCM auth tags are 16 bytes. Reject a truncated tag explicitly — a short tag
  // weakens integrity, and Admin-SDK writes to the deny-all secret doc bypass
  // any client-side validation. `authTagLength` also pins the decipher to 16.
  if (tag.length !== 16) {
    throw new Error("Invalid authentication tag length");
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    Buffer.from(enc.iv, "base64"),
    { authTagLength: 16 },
  );
  decipher.setAuthTag(tag);
  const plaintext = Buffer.concat([
    decipher.update(Buffer.from(enc.ciphertext, "base64")),
    decipher.final(),
  ]);
  return plaintext.toString("utf8");
}
