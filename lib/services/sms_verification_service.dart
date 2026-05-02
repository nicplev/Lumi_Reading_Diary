import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Handle returned by [SmsVerificationService.sendEnrollmentCode] and
/// [SmsVerificationService.sendLoginCode]. [verificationId] is the opaque
/// token Firebase returns after SMS delivery; [resendToken] is Android-only
/// and lets callers force a resend without hammering the default timer.
class SmsCodeHandle {
  final String verificationId;
  final int? resendToken;

  const SmsCodeHandle({
    required this.verificationId,
    this.resendToken,
  });
}

/// Thin wrapper around Firebase's phone auth + multi-factor APIs so the
/// registration and login flows stay focused on UI state instead of juggling
/// four async callbacks.
///
/// Used for teacher + parent SMS MFA. Admin/school-admin auth lives outside
/// this file and uses TOTP (Google Authenticator) instead.
class SmsVerificationService {
  SmsVerificationService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;
  // NOTE: We do NOT set `appVerificationDisabledForTesting` here. While that
  // flag works for primary phone sign-in, Firebase rejects the resulting
  // session token at the multi-factor enroll endpoint with
  // `invalid-user-token`. Simulator testing therefore goes through the
  // standard reCAPTCHA fallback (Safari opens, user taps the checkbox,
  // returns via the custom URL scheme). Test phone numbers configured in
  // the Firebase Console still bypass real SMS delivery — they just go
  // through the real verification path on the way in.

  final FirebaseAuth _auth;

  static const _codeTimeout = Duration(seconds: 60);

  /// Very loose E.164 check — enforces leading `+` and 8–15 digits. Firebase
  /// will reject anything fully malformed on the wire.
  static bool isValidE164(String value) =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim());

  /// Sends an SMS enrollment code for [user]. Returns once Firebase confirms
  /// the SMS was dispatched (or throws if it couldn't be).
  ///
  /// The [forceResendingToken] lets the caller trigger a resend without
  /// waiting for the previous timer to expire (Android only).
  Future<SmsCodeHandle> sendEnrollmentCode({
    required User user,
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    final session = await user.multiFactor.getSession();
    final completer = Completer<SmsCodeHandle>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      multiFactorSession: session,
      timeout: _codeTimeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (_) {
        // MFA enrollment requires the SMS code regardless of auto-retrieval;
        // we ignore this callback and wait for codeSent.
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(SmsCodeHandle(
            verificationId: verificationId,
            resendToken: resendToken,
          ));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );

    return completer.future;
  }

  /// Enrolls [phoneNumber] as a second factor on [user] using the SMS code
  /// the user just typed in. Must be called with the [verificationId]
  /// returned from [sendEnrollmentCode].
  Future<void> enrollPhoneFactor({
    required User user,
    required String verificationId,
    required String smsCode,
    required String phoneNumber,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final assertion = PhoneMultiFactorGenerator.getAssertion(credential);
    await user.multiFactor.enroll(assertion, displayName: phoneNumber);
  }

  /// Whether [user] already has an SMS factor enrolled. Used by the parent
  /// dual-flow (existing account linking a new child) to skip the enrollment
  /// stages when MFA is already set up.
  Future<bool> hasPhoneFactor(User user) async {
    final factors = await user.multiFactor.getEnrolledFactors();
    return factors.any((f) => f.factorId == 'phone');
  }

  /// Sends the SMS challenge for an MFA login. Call this from
  /// [FirebaseAuthMultiFactorException.resolver] when the user signs in and
  /// Firebase requires a second factor.
  Future<SmsCodeHandle> sendLoginCode({
    required MultiFactorResolver resolver,
    int? forceResendingToken,
  }) async {
    if (resolver.hints.isEmpty) {
      throw StateError('MultiFactorResolver returned no hints');
    }
    final hint = resolver.hints.first;
    if (hint is! PhoneMultiFactorInfo) {
      throw StateError('Only phone MFA is supported for parent/teacher login');
    }

    final completer = Completer<SmsCodeHandle>();
    await _auth.verifyPhoneNumber(
      multiFactorSession: resolver.session,
      multiFactorInfo: hint,
      timeout: _codeTimeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (_) {},
      verificationFailed: (FirebaseAuthException e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(SmsCodeHandle(
            verificationId: verificationId,
            resendToken: resendToken,
          ));
        }
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return completer.future;
  }

  /// Completes an MFA login after the user types in the SMS code.
  Future<UserCredential> resolveLogin({
    required MultiFactorResolver resolver,
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final assertion = PhoneMultiFactorGenerator.getAssertion(credential);
    return resolver.resolveSignIn(assertion);
  }

  /// Surfaces a human-readable message for the Firebase error codes we see
  /// most often. Falls back to [FirebaseAuthException.message] if unknown.
  /// In debug builds, the underlying error code is appended so we can
  /// diagnose new failure modes without a console roundtrip.
  static String friendlyError(FirebaseAuthException e) {
    final base = switch (e.code) {
      'invalid-phone-number' =>
        'That phone number doesn\'t look right. Use Australian format (e.g. 0400 000 000).',
      'invalid-verification-code' =>
        'The code doesn\'t match. Please try again.',
      'invalid-verification-id' || 'session-expired' =>
        'That code expired. Tap resend and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait a few minutes before trying again.',
      'quota-exceeded' =>
        'SMS quota reached for now. Please try again later.',
      'missing-phone-number' => 'Please enter your phone number.',
      'second-factor-already-in-use' =>
        'This phone number is already set up as a second factor on another account.',
      'unsupported-first-factor' =>
        'Your account type doesn\'t support phone MFA.',
      'invalid-user-token' || 'user-token-expired' =>
        'Your sign-in session expired. Please close this and start signup again.',
      _ => e.message ?? 'Something went wrong. Please try again.',
    };
    // Include the raw code in debug builds so we can diagnose unfamiliar
    // failures without scraping the simulator console.
    if (kDebugMode) {
      return '$base\n\n[debug: ${e.code}]';
    }
    return base;
  }
}
