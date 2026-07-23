import { randomInt } from 'crypto';

// Unambiguous alphabet — no 0/O, 1/l/I — so temp passwords are easy to read
// aloud, copy, and retype from an email. Mixes upper, lower, and digits.
const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER = 'abcdefghijkmnpqrstuvwxyz';
const DIGITS = '23456789';
// Small, email-safe symbol set that still counts as a "special character" for
// the Firebase Auth password policy.
const SYMBOLS = '!@#$%*-_?';
const ALL = UPPER + LOWER + DIGITS + SYMBOLS;

/**
 * Generate a readable temporary password for an admin-created staff account.
 * 16 chars, guaranteed to include at least one upper, lower, digit AND symbol,
 * so it satisfies the 14+/complexity policy (A2) by construction. Server-only
 * (uses Node crypto). Admin-SDK writes bypass the Firebase console policy, so
 * compliance is guaranteed here.
 */
export function generateTempPassword(length = 16): string {
  const chars: string[] = [
    UPPER[randomInt(UPPER.length)],
    LOWER[randomInt(LOWER.length)],
    DIGITS[randomInt(DIGITS.length)],
    SYMBOLS[randomInt(SYMBOLS.length)],
  ];
  for (let i = chars.length; i < length; i++) {
    chars.push(ALL[randomInt(ALL.length)]);
  }
  // Fisher–Yates shuffle so the guaranteed chars aren't always in front.
  for (let i = chars.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}
