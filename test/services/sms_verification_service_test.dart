import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/sms_verification_service.dart';

void main() {
  group('SmsVerificationService.friendlyError', () {
    test('hides raw Firebase MFA credential errors', () {
      final message = SmsVerificationService.friendlyError(
        FirebaseAuthException(
          code: 'invalid-credential',
          message: 'The multifactor verification code used to create the auth '
              'credential is invalid. Re-collect the verification code and be '
              'sure to use the verification code provided by the user.',
        ),
      );

      expect(message, contains('fresh code'));
      expect(message, isNot(contains('auth credential')));
      expect(message, isNot(contains('multifactor verification code')));
    });

    test('keeps expired code guidance actionable', () {
      final message = SmsVerificationService.friendlyError(
        FirebaseAuthException(code: 'session-expired'),
      );

      expect(message, contains('Tap resend'));
    });
  });
}
