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
  }) {
    return _smsService.sendPrimaryPhoneCode(
      phoneNumberE164: phoneE164,
      forceResendingToken: forceResendingToken,
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

    await user.multiFactor.unenroll(factorUid: factorUid);
    await user.reload();
    await _functions.httpsCallable('syncUserMfaProfileState').call({
      'enabled': false,
      'role': role.name,
      'schoolId': schoolId,
    });
  }
}
