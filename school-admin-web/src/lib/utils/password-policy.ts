// Password policy for admin-set staff passwords (A2). Mirrors the Firebase Auth
// console policy — 14+ chars with an upper, lower, digit and special character.
// Passwords set via the Admin SDK (createUser) bypass the console policy, so
// this is the server-side gate for the portal's "Add Staff" flow; it also drives
// the client modal's inline validation so the two never drift.
export const PASSWORD_MIN_LENGTH = 14;

/** The first unmet requirement as a human phrase, or null if the password is strong. */
export function passwordIssue(pw: string): string | null {
  if (pw.length < PASSWORD_MIN_LENGTH) return `at least ${PASSWORD_MIN_LENGTH} characters`;
  if (!/[A-Z]/.test(pw)) return 'an uppercase letter';
  if (!/[a-z]/.test(pw)) return 'a lowercase letter';
  if (!/[0-9]/.test(pw)) return 'a number';
  if (!/[^A-Za-z0-9]/.test(pw)) return 'a special character';
  return null;
}

export function isStrongPassword(pw: string): boolean {
  return passwordIssue(pw) === null;
}

export const PASSWORD_REQUIREMENT_TEXT =
  `Must be at least ${PASSWORD_MIN_LENGTH} characters and include an uppercase letter, a lowercase letter, a number and a special character.`;
