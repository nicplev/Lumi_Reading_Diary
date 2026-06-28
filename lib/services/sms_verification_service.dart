import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/services/functions_instance.dart';

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

/// Outcome of [SmsVerificationService.completeMfaSignup].
enum MfaSignupOutcome {
  /// A fresh session was re-established via the custom token — go to home.
  sessionReady,

  /// The custom-token sign-in couldn't complete (e.g. MFA-challenged). The
  /// account is fully set up server-side; route the user to the login screen.
  needsLogin,
}

/// Thin wrapper around Firebase's phone auth + multi-factor APIs so the
/// registration and login flows stay focused on UI state instead of juggling
/// four async callbacks.
///
/// Used for teacher + parent SMS MFA. Admin/school-admin auth lives outside
/// this file and uses TOTP (Google Authenticator) instead.
class SmsVerificationService {
  SmsVerificationService({FirebaseAuth? auth, FirebaseFunctions? functions})
      : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? lumiFunctions;
  // NOTE: `appVerificationDisabledForTesting` is set globally in DEBUG builds
  // (see main.dart) so configured test phone numbers work on the iOS Simulator
  // without the reCAPTCHA fallback. It was historically avoided because it
  // broke the OLD client `multiFactor.enroll` endpoint with `invalid-user-token`
  // — but signup now enrols MFA server-side (linkPhoneAndEnrollMfa → Admin SDK),
  // so that path is gone and the flag is safe. Never set in release builds.

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  static const _codeTimeout = Duration(seconds: 60);

  /// Very loose E.164 check — enforces leading `+` and 8–15 digits. Firebase
  /// will reject anything fully malformed on the wire.
  static bool isValidE164(String value) =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value.trim());

  /// Calls the `requestSmsVerification` Cloud Function to check the
  /// per-phone-number daily rate limit before triggering an actual SMS.
  ///
  /// Behaviour:
  ///  - On `resource-exhausted` from the gate, rethrows as a
  ///    `FirebaseAuthException(code: 'quota-exceeded')` so the existing
  ///    [friendlyError] mapping surfaces a clean message to the user.
  ///  - On any other gate error (network down, server bug, etc.), swallows
  ///    it and lets the SMS attempt proceed. We never want to lock out
  ///    legitimate users because our own anti-abuse plumbing is broken.
  ///  - When [phoneE164] is null or fails E.164 validation, skips the gate
  ///    entirely (e.g. the MFA login path where the phone may come back
  ///    masked from the resolver hint).
  Future<void> _checkRateLimit({
    required String? phoneE164,
    required String purpose,
  }) async {
    if (phoneE164 == null) return;
    final trimmed = phoneE164.trim();
    if (!isValidE164(trimmed)) return;
    try {
      final callable = _functions.httpsCallable('requestSmsVerification');
      await callable.call<Map<String, dynamic>>({
        'phoneE164': trimmed,
        'purpose': purpose,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw FirebaseAuthException(
          code: 'quota-exceeded',
          message: e.message ??
              'SMS quota reached for this number. Please try again later.',
        );
      }
      if (kDebugMode) {
        debugPrint('[phone-auth] rate-limit gate non-fatal error: '
            'code=${e.code} message=${e.message}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[phone-auth] rate-limit gate threw: $e');
      }
    }
  }

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
    await _checkRateLimit(phoneE164: phoneNumber, purpose: 'enrollment');
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
  ///
  /// NOTE: Identity Platform blocks this client-side enroll until the user's
  /// email is verified. Lumi's signup enrolls MFA before email verification,
  /// so the registration flow uses [linkPhoneAndEnrollMfa] (server-side)
  /// instead. This direct path only works on already-verified-email accounts.
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

  /// Completes an email+password signup that needs phone MFA, WITHOUT requiring
  /// a verified email, and finalises the account server-side.
  ///
  /// Identity Platform blocks MFA enrolment until the email is verified (Admin
  /// SDK included), AND enrolling MFA revokes the client's session — so the
  /// finalisation (parent/teacher doc + indexes + child link) must happen
  /// server-side. This: proves phone ownership by LINKING the SMS-verified
  /// credential, then calls `enrollLinkedPhoneAsMfa`, which enrols the factor,
  /// unlinks the primary phone provider, finalises the signup, and returns a
  /// custom token. We sign in with that token to re-establish a session.
  ///
  /// Returns [MfaSignupOutcome.sessionReady] when a fresh session was set up
  /// (proceed to home), or [MfaSignupOutcome.needsLogin] when the custom-token
  /// sign-in was MFA-challenged (the account is fully set up; route to login).
  /// Pair with [sendPrimaryPhoneCode] for the SMS send (no multi-factor session).
  Future<MfaSignupOutcome> completeMfaSignup({
    required User user,
    required String verificationId,
    required String smsCode,
    required String phoneNumber,
    required String role,
    required String schoolId,
    required String fullName,
    String? email,
    String? relationshipLabel,
    String? linkCode,
  }) async {
    // Ensure the session is fresh before linking. A stale/expired token — which
    // happens when the app cold-starts onto a session whose account was deleted
    // server-side, or on the iOS Simulator — makes linkWithCredential fail with
    // `user-token-expired`. Refresh first; if the account is genuinely gone,
    // sign out so the NEXT signup attempt starts from a clean session (rather
    // than re-hitting the dead one every retry).
    try {
      await user.reload();
      await user.getIdToken(true);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-token-expired' ||
          e.code == 'user-not-found' ||
          e.code == 'user-disabled') {
        await _auth.signOut();
        throw FirebaseAuthException(
          code: 'session-stale',
          message: 'Your sign-in session expired. Please close this and '
              'start signup again.',
        );
      }
      rethrow;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    // Prove ownership: link the verified phone to this account.
    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'provider-already-linked':
          // Phone already linked to THIS account from an earlier attempt —
          // idempotent retry; fall through to enrolment.
          break;
        case 'credential-already-in-use':
          // The phone belongs to a DIFFERENT account (it's already registered,
          // e.g. as a phone-primary login). Surface clearly instead of letting
          // the server report a confusing "not verified for this account".
          throw FirebaseAuthException(
            code: 'phone-already-registered',
            message: 'This phone number is already registered to another '
                'account. Use a different number, or log in instead.',
          );
        case 'user-token-expired':
        case 'user-mismatch':
        case 'requires-recent-login':
          // Dead/expired session — sign out so the next attempt is clean.
          await _auth.signOut();
          throw FirebaseAuthException(
            code: 'session-stale',
            message: 'Your sign-in session expired. Please close this and '
                'start signup again.',
          );
        default:
          // Wrong code etc. surface via friendlyError as usual.
          rethrow;
      }
    }

    // Enroll + finalise the signup server-side (the client's session is dead
    // after the enrol). Re-shape any function error into a FirebaseAuthException
    // so the existing [friendlyError] mapping + modal handling surface a clean
    // message.
    final Map<String, dynamic> result;
    try {
      final resp = await _functions
          .httpsCallable('enrollLinkedPhoneAsMfa')
          .call<Map<String, dynamic>>({
        'phoneE164': phoneNumber,
        'displayName': phoneNumber,
        'role': role,
        'schoolId': schoolId,
        'fullName': fullName,
        if (email != null && email.isNotEmpty) 'email': email,
        if (relationshipLabel != null) 'relationshipLabel': relationshipLabel,
        if (linkCode != null) 'linkCode': linkCode,
      });
      result = Map<String, dynamic>.from(resp.data as Map? ?? const {});
    } on FirebaseFunctionsException catch (e) {
      throw FirebaseAuthException(
        code: e.code == 'already-exists'
            ? 'second-factor-already-in-use'
            : 'mfa-enroll-failed',
        message: e.message ?? 'Could not complete signup. Please try again.',
      );
    }

    // Re-establish a session with the returned custom token (the enrol revoked
    // the old one). If the token sign-in is MFA-challenged, the account is still
    // fully set up server-side — tell the caller to route to login.
    final customToken = result['customToken'] as String?;
    if (customToken == null || customToken.isEmpty) {
      return MfaSignupOutcome.needsLogin;
    }
    try {
      await _auth.signInWithCustomToken(customToken);
      return MfaSignupOutcome.sessionReady;
    } on FirebaseAuthException {
      return MfaSignupOutcome.needsLogin;
    }
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
    // PhoneMultiFactorInfo.phoneNumber is E.164 when Firebase has it;
    // some platforms / privacy modes return a masked value. The gate
    // handles both cases — invalid E.164 falls through without enforcement.
    await _checkRateLimit(phoneE164: hint.phoneNumber, purpose: 'login');

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

  /// Sends an SMS verification code as a PRIMARY auth challenge — used by
  /// the phone-only registration path and the "Sign in with phone" login
  /// branch. Unlike [sendEnrollmentCode], no [multiFactorSession] is attached,
  /// so the resulting credential signs the user in directly rather than
  /// enrolling a second factor.
  /// [onCodeSentPersist] fires synchronously inside Firebase's `codeSent`
  /// callback — *before* the future returned by this method completes,
  /// and regardless of whether the original caller widget is still
  /// mounted. The phone-auth recovery flow uses this hook to persist the
  /// verification ID + flow context to Hive at the exact moment Firebase
  /// hands us a usable credential, so iOS reCAPTCHA modal disposal (or
  /// any other widget teardown mid-flow) can't drop the SMS step on the
  /// floor.
  Future<SmsCodeHandle> sendPrimaryPhoneCode({
    required String phoneNumberE164,
    int? forceResendingToken,
    void Function(SmsCodeHandle handle)? onCodeSentPersist,
  }) async {
    if (kDebugMode) {
      debugPrint(
          '[phone-auth] sendPrimaryPhoneCode → start phone=$phoneNumberE164 resendToken=$forceResendingToken');
    }
    await _checkRateLimit(phoneE164: phoneNumberE164, purpose: 'primary');
    final completer = Completer<SmsCodeHandle>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumberE164,
      timeout: _codeTimeout,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (_) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] sendPrimaryPhoneCode → verificationCompleted (auto-retrieval; ignored — UI waits for manual entry)');
        }
        // Android auto-retrieval. Ignore: the calling UI is set up for
        // manual entry and the test/dev phone numbers don't auto-retrieve.
      },
      verificationFailed: (FirebaseAuthException e) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] sendPrimaryPhoneCode → verificationFailed code=${e.code} message=${e.message} details=${e.toString()}');
        }
        if (!completer.isCompleted) completer.completeError(e);
      },
      codeSent: (verificationId, resendToken) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] sendPrimaryPhoneCode → codeSent verificationIdLen=${verificationId.length} resendToken=$resendToken');
        }
        final handle = SmsCodeHandle(
          verificationId: verificationId,
          resendToken: resendToken,
        );
        // Persist BEFORE completing the future. If the caller widget is
        // already gone, the await chain bails on the !mounted check
        // immediately after — but the recovery record has already been
        // written by then.
        if (onCodeSentPersist != null) {
          try {
            onCodeSentPersist(handle);
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint(
                  '[phone-auth] sendPrimaryPhoneCode → onCodeSentPersist threw: $e\n$st');
            }
          }
        }
        if (!completer.isCompleted) completer.complete(handle);
      },
      codeAutoRetrievalTimeout: (_) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] sendPrimaryPhoneCode → codeAutoRetrievalTimeout (60s elapsed without auto-retrieval)');
        }
      },
    );

    return completer.future;
  }

  /// Completes a primary phone sign-in with the SMS code the user typed in.
  /// Pair with [sendPrimaryPhoneCode]. The returned [UserCredential.user]
  /// is the signed-in account — same shape as the email/password path.
  Future<UserCredential> signInWithPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    if (kDebugMode) {
      debugPrint(
          '[phone-auth] signInWithPhoneCode → start verificationIdLen=${verificationId.length} smsCodeLen=${smsCode.length}');
    }
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    try {
      final result = await _auth.signInWithCredential(credential);
      if (kDebugMode) {
        debugPrint(
            '[phone-auth] signInWithPhoneCode → success uid=${result.user?.uid} phone=${result.user?.phoneNumber}');
      }
      return result;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[phone-auth] signInWithPhoneCode → failed code=${e.code} message=${e.message}');
      }
      rethrow;
    }
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
      // Project-level: SMS multi-factor auth disabled (or Phone provider/region
      // not enabled) for the Firebase project. End users can't fix this, so keep
      // it calm and point them at support rather than leaking the raw
      // "SMS based MFA not enabled" provider message.
      'operation-not-allowed' =>
        'Phone verification isn\'t available right now. Please try again shortly, or contact support if it keeps happening.',
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
