import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/services/functions_instance.dart';
import '../data/models/user_model.dart';
import 'sms_verification_service.dart';

class MfaStatus {
  final bool enabled;
  final String? phoneNumber;
  final String? factorUid;
  final bool hasPhonePrimary;
  final bool hasEmailPrimary;

  const MfaStatus({
    required this.enabled,
    this.phoneNumber,
    this.factorUid,
    required this.hasPhonePrimary,
    required this.hasEmailPrimary,
  });
}

class MfaSettingsService {
  MfaSettingsService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    SmsVerificationService? smsService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? lumiFunctions,
        _smsService = smsService ?? SmsVerificationService();

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final SmsVerificationService _smsService;

  Future<MfaStatus> loadStatus() async {
    final current = _auth.currentUser;
    if (current == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'You need to be signed in to manage MFA.',
      );
    }

    await current.reload();
    final user = _auth.currentUser ?? current;
    final factors = await user.multiFactor.getEnrolledFactors();
    PhoneMultiFactorInfo? phoneFactor;
    for (final factor in factors) {
      if (factor is PhoneMultiFactorInfo) {
        phoneFactor = factor;
        break;
      }
    }

    return MfaStatus(
      enabled: phoneFactor != null,
      phoneNumber: phoneFactor?.phoneNumber,
      factorUid: phoneFactor?.uid,
      hasPhonePrimary: (user.phoneNumber ?? '').isNotEmpty,
      hasEmailPrimary: (user.email ?? '').isNotEmpty,
    );
  }

  Future<SmsCodeHandle> sendEnableCode({
    required String phoneE164,
    int? forceResendingToken,
    void Function(SmsCodeHandle handle)? onCodeSentPersist,
  }) {
    return _smsService.sendPrimaryPhoneCode(
      phoneNumberE164: phoneE164,
      forceResendingToken: forceResendingToken,
      onCodeSentPersist: onCodeSentPersist,
    );
  }

  Future<MfaSignupOutcome> enableWithCode({
    required String verificationId,
    required String smsCode,
    required String phoneE164,
    required UserRole role,
    required String schoolId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'You need to be signed in to manage MFA.',
      );
    }
    return _smsService.completeOptionalMfaEnrollment(
      user: user,
      verificationId: verificationId,
      smsCode: smsCode,
      phoneNumber: phoneE164,
      role: role.name,
      schoolId: schoolId,
    );
  }

  Future<void> disable({
    required MfaStatus status,
    required UserRole role,
    required String schoolId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'You need to be signed in to manage MFA.',
      );
    }
    final factorUid = status.factorUid;
    if (factorUid == null || factorUid.isEmpty) return;

    try {
      await user.multiFactor.unenroll(factorUid: factorUid);
    } on FirebaseAuthException catch (_) {
      // iOS can throw "no second factor matching the identifier" even when the
      // unenroll actually removed the factor. Right after the call the local
      // session still lists the factor, so a single reload() isn't enough —
      // force a server round-trip and re-check a few times before deciding it
      // genuinely failed. Only surface the error if it's really still enrolled.
      if (await _isFactorStillEnrolled(user, factorUid)) rethrow;
    }
    await user.reload();
    await _functions.httpsCallable('syncUserMfaProfileState').call({
      'enabled': false,
      'role': role.name,
      'schoolId': schoolId,
    });
  }

  /// Whether [factorUid] is still enrolled, forcing a fresh server round-trip
  /// before reading. iOS's firebase_auth keeps the just-removed factor in the
  /// local session even after a plain `reload()`, so we refresh the ID token
  /// and re-check up to three times; the moment it's gone we return false.
  Future<bool> _isFactorStillEnrolled(User user, String factorUid) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await user.getIdToken(true);
      } catch (_) {
        // A failed refresh shouldn't mask a successful unenroll — fall through
        // to reload() and let the factor check decide.
      }
      await user.reload();
      final refreshed = _auth.currentUser ?? user;
      final factors = await refreshed.multiFactor.getEnrolledFactors();
      if (!factors.any((f) => f.uid == factorUid)) return false;
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return true;
  }
}
