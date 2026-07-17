import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/exceptions/session_exceptions.dart';

FirebaseException firebaseError(String code) => FirebaseException(
      plugin: 'test',
      code: code,
    );

void main() {
  group('isTerminalAuthSessionError', () {
    test('recognises revoked, expired, disabled and missing accounts', () {
      for (final code in [
        'invalid-user-token',
        'user-token-expired',
        'user-disabled',
        'user-not-found',
        'unauthenticated',
      ]) {
        expect(isTerminalAuthSessionError(firebaseError(code)), isTrue,
            reason: code);
      }
    });

    test('does not log out for transient connectivity/service failures', () {
      for (final code in [
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
        'too-many-requests',
      ]) {
        expect(isTerminalAuthSessionError(firebaseError(code)), isFalse,
            reason: code);
      }
    });
  });

  group('isInvalidOwnProfileSessionError', () {
    test('treats own-profile permission denial as session invalidation', () {
      expect(
        isInvalidOwnProfileSessionError(firebaseError('permission-denied')),
        isTrue,
      );
    });

    test('retains retry behaviour for transient profile-read failures', () {
      expect(
        isInvalidOwnProfileSessionError(firebaseError('unavailable')),
        isFalse,
      );
    });
  });
}
