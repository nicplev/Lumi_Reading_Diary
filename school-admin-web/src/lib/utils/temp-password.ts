import { randomInt } from 'crypto';

// Unambiguous alphabet — no 0/O, 1/l/I — so temp passwords are easy to read
// aloud, copy, and retype from an email. Mixes upper, lower, and digits.
const UPPER = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
const LOWER = 'abcdefghijkmnpqrstuvwxyz';
const DIGITS = '23456789';
const ALL = UPPER + LOWER + DIGITS;

/**
 * Generate a readable temporary password for an admin-created staff account.
 * 12 chars (well above Firebase Auth's 6-char minimum), guaranteed to include
 * at least one upper, lower, and digit. Server-only (uses Node crypto).
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
  return chars.join('');
}
