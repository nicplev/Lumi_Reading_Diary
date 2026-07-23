/// Shared password policy for non-student accounts (A2).
///
/// Mirrors the Firebase Auth console policy and the web portal validator: at
/// least 14 characters with an uppercase letter, a lowercase letter, a number
/// and a special character. Keeping one source of truth stops the rule drifting
/// between the parent-signup, teacher-signup and school-onboarding screens
/// (which each had their own inline 8-char check).
library;

const int kMinPasswordLength = 14;

/// The first unmet requirement as a short phrase (e.g. 'a special character'),
/// or null if [value] satisfies the policy.
String? passwordIssue(String value) {
  if (value.length < kMinPasswordLength) {
    return 'at least $kMinPasswordLength characters';
  }
  if (!RegExp(r'[A-Z]').hasMatch(value)) return 'an uppercase letter';
  if (!RegExp(r'[a-z]').hasMatch(value)) return 'a lowercase letter';
  if (!RegExp(r'[0-9]').hasMatch(value)) return 'a number';
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(value)) return 'a special character';
  return null;
}

/// Whether [value] satisfies the full password policy.
bool isPasswordCompliant(String value) => passwordIssue(value) == null;

/// One-line requirement text for helper/hint copy.
const String kPasswordRequirementText =
    'At least $kMinPasswordLength characters with an uppercase and lowercase '
    'letter, a number and a special character.';
