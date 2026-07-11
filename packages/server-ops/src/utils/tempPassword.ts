import { randomInt } from "crypto";

// Readable temp-password generator, ported for the demo-day day password.
// TODO: this is the THIRD copy — the other two are functions/src/temp_password.ts
// and school-admin-web/src/lib/utils/temp-password.ts. Hoist all three into one
// shared module when convenient (out of scope for the demo-day work).
//
// Unambiguous alphabet — no 0/O, 1/l/I — so the password is easy to read aloud
// over Zoom, copy, and retype from an email.
const UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const LOWER = "abcdefghijkmnpqrstuvwxyz";
const DIGITS = "23456789";
const ALL = UPPER + LOWER + DIGITS;

/**
 * Generate a readable temporary password. 12 chars by default (well above
 * Firebase Auth's 6-char minimum), guaranteed to include at least one upper,
 * lower, and digit.
 */
export function generateTempPassword(length = 12): string {
  const chars: string[] = [
    UPPER[randomInt(UPPER.length)],
    LOWER[randomInt(LOWER.length)],
    DIGITS[randomInt(DIGITS.length)],
  ];
  for (let i = chars.length; i < length; i++) {
    chars.push(ALL[randomInt(ALL.length)]);
  }
  // Fisher–Yates shuffle so the guaranteed chars aren't always in front.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}
