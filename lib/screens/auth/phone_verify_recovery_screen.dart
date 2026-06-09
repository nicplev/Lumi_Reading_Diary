import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/exceptions/linking_exceptions.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/user_school_index_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/parent_linking_service.dart';
import '../../services/phone_verification_recovery_service.dart';
import '../../services/sms_verification_service.dart';
import 'widgets/auth_bottom_sheet_overlay.dart';

/// Resumes an in-flight Firebase phone verification that was orphaned by
/// an iOS reCAPTCHA modal-disposal (or any other widget teardown / app
/// relaunch mid-flow). Reads the pending record from
/// [PhoneVerificationRecoveryService] and shows a minimal SMS-code entry
/// screen, then finalises whichever auth flow originally requested the
/// verification.
class PhoneVerifyRecoveryScreen extends StatefulWidget {
  const PhoneVerifyRecoveryScreen({super.key});

  @override
  State<PhoneVerifyRecoveryScreen> createState() =>
      _PhoneVerifyRecoveryScreenState();
}

class _PhoneVerifyRecoveryScreenState extends State<PhoneVerifyRecoveryScreen> {
  static const Duration _resendCooldown = Duration(seconds: 30);

  final SmsVerificationService _smsService = SmsVerificationService();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final ParentLinkingService _linkingService = ParentLinkingService();
  final TextEditingController _codeController = TextEditingController();

  PendingPhoneVerification? _record;
  bool _loading = true;
  bool _busy = false;
  String? _errorMessage;
  DateTime? _lastSendAt;
  Timer? _resendTicker;
  int _resendRemainingSec = 0;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  @override
  void dispose() {
    _resendTicker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadRecord() async {
    final record = await PhoneVerificationRecoveryService.instance.peek();
    if (!mounted) return;
    if (record == null) {
      // Race: peek returned null (expired or already cleared). Route
      // back to login — no recovery to perform.
      context.go('/auth/login');
      return;
    }
    setState(() {
      _record = record;
      _loading = false;
    });
  }

  bool get _codeValid => RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim());

  int _computeResendRemainingSec() {
    final last = _lastSendAt;
    if (last == null) return 0;
    final elapsed = DateTime.now().difference(last);
    final left = _resendCooldown - elapsed;
    return left.isNegative ? 0 : left.inSeconds;
  }

  void _startResendCountdown() {
    _resendTicker?.cancel();
    _lastSendAt = DateTime.now();
    _resendRemainingSec = _resendCooldown.inSeconds;
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _computeResendRemainingSec();
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _resendRemainingSec = 0);
      } else {
        setState(() => _resendRemainingSec = remaining);
      }
    });
  }

  Future<void> _resend() async {
    final record = _record;
    if (record == null || _busy || _resendRemainingSec > 0) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: record.phoneE164,
        forceResendingToken: record.resendToken,
        onCodeSentPersist: (h) {
          final updated = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: record.phoneE164,
            mode: record.mode,
            contextJson: record.contextJson,
            savedAt: DateTime.now(),
          );
          unawaited(PhoneVerificationRecoveryService.instance.save(updated));
        },
      );
      if (!mounted) return;
      setState(() {
        _record = PendingPhoneVerification(
          verificationId: handle.verificationId,
          resendToken: handle.resendToken,
          phoneE164: record.phoneE164,
          mode: record.mode,
          contextJson: record.contextJson,
          savedAt: DateTime.now(),
        );
      });
      _startResendCountdown();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Couldn\'t resend the code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final record = _record;
    if (record == null || _busy || !_codeValid) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final cred = await _smsService.signInWithPhoneCode(
        verificationId: record.verificationId,
        smsCode: _codeController.text.trim(),
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'Sign-in did not return a user.',
        );
      }

      switch (record.mode) {
        case PhoneVerificationMode.phonePrimaryRegistration:
          await _finishRegistration(uid: uid, record: record);
          break;
        case PhoneVerificationMode.phoneLogin:
          await _finishLogin(uid: uid, record: record);
          break;
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Verification failed: ${e.toString().replaceAll('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Phone-primary registration tail. Writes the parent doc, indexes
  /// the phone, links to the student, clears the recovery record, and
  /// navigates home.
  Future<void> _finishRegistration({
    required String uid,
    required PendingPhoneVerification record,
  }) async {
    final ctx = record.contextJson;
    final schoolId = ctx['schoolId'] as String?;
    final studentId = ctx['studentId'] as String?;
    final linkCodeValue = ctx['linkCodeValue'] as String?;
    final fullName = (ctx['fullName'] as String?) ?? '';
    final relationshipLabel = ctx['relationshipLabel'] as String?;
    if (schoolId == null || studentId == null || linkCodeValue == null) {
      throw StateError('Recovery context missing required fields.');
    }

    final parentRef = _firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('parents')
        .doc(uid);
    final existingDoc = await parentRef.get();

    if (!existingDoc.exists) {
      final parentUser = UserModel(
        id: uid,
        email: null,
        fullName: fullName,
        role: UserRole.parent,
        schoolId: schoolId,
        linkedChildren: const [],
        createdAt: DateTime.now(),
        isActive: true,
        phoneNumber: record.phoneE164,
        phoneVerified: true,
        relationshipLabel: relationshipLabel,
      );
      await parentRef.set(parentUser.toFirestore());
      try {
        await _firebaseService.firestore
            .collection('schools')
            .doc(schoolId)
            .update({'parentCount': FieldValue.increment(1)});
      } catch (_) {
        // Non-critical; continue.
      }
    } else {
      // linkedChildren is owned by the linkParentToStudent callable below.
      final update = <String, dynamic>{
        'fullName': fullName,
        'phoneNumber': record.phoneE164,
        'phoneVerified': true,
      };
      if (relationshipLabel != null) {
        update['relationshipLabel'] = relationshipLabel;
      }
      await parentRef.update(update);
    }

    await UserSchoolIndexService().createOrUpdatePhoneIndex(
      phoneE164: record.phoneE164,
      schoolId: schoolId,
      userType: 'parent',
      userId: uid,
    );

    try {
      await _linkingService.linkParentToStudent(
        code: linkCodeValue,
        parentUserId: uid,
        parentEmail: null,
      );
    } on AlreadyLinkedException {
      // Already linked — treat as success.
    }

    final fresh = await parentRef.get();
    if (fresh.exists) {
      NotificationService.instance
          .onParentAuthenticated(UserModel.fromFirestore(fresh));
    }

    await PhoneVerificationRecoveryService.instance.clear();
    if (!mounted) return;
    context.go(AppRouter.getHomeRouteForRole(UserRole.parent));
  }

  /// Phone-login tail. Resolves the school via the phone hash, loads
  /// the user doc, clears the recovery record, and navigates.
  Future<void> _finishLogin({
    required String uid,
    required PendingPhoneVerification record,
  }) async {
    final indexService = UserSchoolIndexService();
    final indexResult =
        await indexService.lookupSchoolByPhone(record.phoneE164);
    if (indexResult == null) {
      await _firebaseService.signOut();
      await PhoneVerificationRecoveryService.instance.clear();
      if (!mounted) return;
      setState(() => _errorMessage =
          'We couldn\'t find an account for that phone number. If you\'re new, tap "I have a code" to register.');
      return;
    }

    final schoolId = indexResult['schoolId'] as String;
    final userType = indexResult['userType'] as String;
    final collection = userType == 'parent' ? 'parents' : 'users';
    final doc = await _firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection(collection)
        .doc(uid)
        .get();
    if (!doc.exists) {
      await _firebaseService.signOut();
      await PhoneVerificationRecoveryService.instance.clear();
      if (!mounted) return;
      setState(() => _errorMessage =
          'Your profile is missing. Please contact your school administrator.');
      return;
    }
    final user = UserModel.fromFirestore(doc);

    await _firebaseService.firestore
        .collection('schools')
        .doc(schoolId)
        .collection(collection)
        .doc(uid)
        .update({'lastLoginAt': FieldValue.serverTimestamp()});

    NotificationService.instance.onParentAuthenticated(user);

    await PhoneVerificationRecoveryService.instance.clear();
    if (!mounted) return;
    context.go(AppRouter.getHomeRouteForRole(user.role));
  }

  Future<void> _cancel() async {
    await PhoneVerificationRecoveryService.instance.clear();
    if (!mounted) return;
    context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    // Loading and missing-record render a transparent placeholder inside the
    // same overlay shell so the splash → recovery handoff stays a single
    // visual transition (no full-screen white flash between loaders).
    if (_loading) {
      return const AuthBottomSheetOverlay(
        debugLabel: 'phone-verify-recovery-overlay',
        dismissOnTapOutside: false,
        card: _LoadingCard(),
      );
    }
    final record = _record;
    if (record == null) {
      return const AuthBottomSheetOverlay(
        debugLabel: 'phone-verify-recovery-overlay',
        dismissOnTapOutside: false,
        card: SizedBox.shrink(),
      );
    }

    return AuthBottomSheetOverlay(
      debugLabel: 'phone-verify-recovery-overlay',
      // Mid-verify accidental dismiss would lose the verificationId — only
      // the explicit Cancel button can leave this screen.
      dismissOnTapOutside: false,
      card: _PhoneVerifyRecoveryCard(
        phoneE164: record.phoneE164,
        codeController: _codeController,
        busy: _busy,
        codeValid: _codeValid,
        resendRemainingSec: _resendRemainingSec,
        errorMessage: _errorMessage,
        onCodeChanged: () {
          setState(() {});
          if (_codeValid && !_busy) _verify();
        },
        onVerify: _verify,
        onResend: _resend,
        onCancel: _cancel,
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.18),
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _PhoneVerifyRecoveryCard extends StatelessWidget {
  const _PhoneVerifyRecoveryCard({
    required this.phoneE164,
    required this.codeController,
    required this.busy,
    required this.codeValid,
    required this.resendRemainingSec,
    required this.errorMessage,
    required this.onCodeChanged,
    required this.onVerify,
    required this.onResend,
    required this.onCancel,
  });

  final String phoneE164;
  final TextEditingController codeController;
  final bool busy;
  final bool codeValid;
  final int resendRemainingSec;
  final String? errorMessage;
  final VoidCallback onCodeChanged;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Eat taps on the card itself so the AuthBottomSheetOverlay's
      // tap-outside (when enabled) doesn't fire from card-area taps.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppColors.charcoal.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row matches the registration modal's _buildHeader
              // shape (centered title + close on the right; no back here
              // because there's nowhere to go back to inside the recovery
              // flow).
              Row(
                children: [
                  const SizedBox(width: 40, height: 40),
                  Expanded(
                    child: Text(
                      'Verify your phone',
                      textAlign: TextAlign.center,
                      style: LumiTextStyles.h3(),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close, size: 22),
                      color: AppColors.charcoal,
                      splashRadius: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'We sent a 6-digit code to $phoneE164. Enter it below to finish signing in.',
                textAlign: TextAlign.center,
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: 6,
                autofocus: true,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '6-digit code',
                  hintText: '123456',
                  prefixIcon: Icon(Icons.sms_outlined),
                ),
                onChanged: (_) => onCodeChanged(),
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorMessage!,
                  style: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 20),
              LumiPrimaryButton(
                onPressed: busy || !codeValid ? null : onVerify,
                text: 'Verify & continue',
                isLoading: busy,
                isFullWidth: true,
              ),
              const SizedBox(height: 8),
              Center(
                child: LumiTextButton(
                  onPressed: busy || resendRemainingSec > 0 ? null : onResend,
                  text: resendRemainingSec > 0
                      ? 'Resend in ${resendRemainingSec}s'
                      : 'Resend code',
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: LumiTextButton(
                  onPressed: busy ? null : onCancel,
                  text: 'Cancel',
                  color: AppColors.charcoal.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
