import 'package:firebase_core/firebase_core.dart';

/// Raised when Lumi can still see a local Firebase user but the server no
/// longer accepts that identity for the signed-in user's own profile.
class InvalidUserSessionException implements Exception {
  const InvalidUserSessionException();

  @override
  String toString() => 'InvalidUserSessionException';
}

const Set<String> _terminalAuthCodes = {
  'invalid-user-token',
  'user-token-expired',
  'user-disabled',
  'user-not-found',
  'unauthenticated',
};

/// Errors from an Auth refresh that mean retrying with the same local session
/// cannot recover. Network/time-out failures are deliberately excluded so
/// Lumi can continue with its cached offline state.
bool isTerminalAuthSessionError(Object error) {
  return error is FirebaseException &&
      _terminalAuthCodes.contains(error.code.toLowerCase());
}

/// The signed-in user's own profile is an authorization boundary. A denied
/// read there means the account was revoked/deactivated, its membership was
/// removed, or the token is no longer accepted. Treating that as "profile not
/// found" leaves a dead Firebase user locally signed in and can loop the login
/// route; it must end the local session instead.
bool isInvalidOwnProfileSessionError(Object error) {
  if (isTerminalAuthSessionError(error)) return true;
  return error is FirebaseException &&
      error.code.toLowerCase() == 'permission-denied';
}
