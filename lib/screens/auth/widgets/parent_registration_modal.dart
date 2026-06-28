import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/linking_exceptions.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/user_school_index_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../data/models/student_link_code_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/analytics_service.dart';
import '../../../services/crash_reporting_service.dart';
import '../../../services/parent_linking_service.dart';
import '../../../services/phone_verification_recovery_service.dart';
import '../../../services/sms_verification_service.dart';
import '../link_code_scanner_screen.dart';
import 'auth_bottom_sheet_overlay.dart';

/// Opens the floating parent registration modal over the current screen.
/// Blurs the background, rises from the bottom, and walks the user through
/// code verification → name → email → password → confirm → success.
Future<void> showParentRegistrationModal(BuildContext context) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      barrierLabel: 'Parent registration',
      // Long, gentle intro; short crisp dismiss so it doesn't linger.
      transitionDuration: const Duration(milliseconds: 850),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const _ParentRegistrationOverlay(),
    ),
  );
}

enum _Stage {
  code,
  name,
  relationship,
  phone,
  email,
  password,
  confirm,
  sms,
  success
}

/// Which Firebase Auth flow drives the SMS step. Decided at the moment the
/// user leaves the `email`/`confirm` stage and persists through `sms` so
/// `_verifySmsAndFinish` knows how to finalise the account.
enum _AuthFlow {
  /// User left email blank — phone is the primary credential. We call
  /// `verifyPhoneNumber` directly (no MFA session) and complete with
  /// `signInWithCredential` on the SMS step.
  phonePrimary,

  /// User supplied email + password — we created (or signed in) an email
  /// account and enrolled phone as an MFA factor. SMS completes enrollment.
  emailMfa,

  /// Email was already in use AND had MFA enrolled — Firebase returned a
  /// resolver; SMS verifies against the existing enrolled phone. Same
  /// behaviour as before the phone-optional change.
  existingMfa,
}

class _ParentRegistrationOverlay extends StatelessWidget {
  const _ParentRegistrationOverlay();

  @override
  Widget build(BuildContext context) {
    return const AuthBottomSheetOverlay(
      debugLabel: 'parent-registration-overlay',
      card: _ParentRegistrationCard(),
    );
  }
}

class _ParentRegistrationCard extends StatefulWidget {
  const _ParentRegistrationCard();

  @override
  State<_ParentRegistrationCard> createState() =>
      _ParentRegistrationCardState();
}

class _ParentRegistrationCardState extends State<_ParentRegistrationCard> {
  final _linkingService = ParentLinkingService();
  final _smsService = SmsVerificationService();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _codeController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  // Free-text relationship label, used only when "Other" is selected.
  final _relationshipOtherController = TextEditingController();

  // Selected relationship: a preset (Mum/Dad/Grandparent/Guardian) or 'Other'.
  String? _relationshipChoice;

  _Stage _stage = _Stage.code;
  bool _busy = false;
  String? _errorMessage;

  StudentLinkCodeModel? _verifiedCode;
  Map<String, dynamic>? _studentInfo;
  UserModel? _createdParent;

  // SMS state. _authFlow is decided when the user transitions out of email
  // or confirm and drives both the SMS send and verify-finish paths.
  _AuthFlow? _authFlow;
  String? _pendingUserId;
  String? _verificationId;
  int? _resendToken;
  DateTime? _lastSendAt;
  Timer? _resendTicker;
  static const _resendCooldown = Duration(seconds: 30);
  // Login-path MFA: set when we signed in an existing MFA-enrolled parent
  // and need to complete the second factor before linking the new student.
  MultiFactorResolver? _loginMfaResolver;
  // Set when the account already exists AND already has phone MFA enrolled.
  // Skips the enrollment write but still goes through a challenge.
  bool _mfaAlreadyEnrolled = false;

  bool _lastNameRevealed = false;
  Timer? _lastNameRevealTimer;
  static const _lastNameRevealThreshold = 2;
  static const _lastNameRevealDelay = Duration(milliseconds: 300);

  // Persistent focus nodes — shared across stage builds so focus survives the
  // AnimatedSwitcher transition when progressive reveal advances the stage.
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    for (final c in [
      _codeController,
      _firstNameController,
      _lastNameController,
      _emailController,
      _passwordController,
      _confirmController,
      _phoneController,
      _smsCodeController,
      _relationshipOtherController,
    ]) {
      c.addListener(() => setState(() {}));
    }
    _firstNameController.addListener(_updateLastNameVisibility);
    _lastNameController.addListener(_updateLastNameVisibility);
    // Progressive reveal: tapping into the peek field commits the stage
    // advance so the previous field compacts to a chip.
    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus &&
          _stage == _Stage.email &&
          _emailValid) {
        _advance(_Stage.password);
      }
    });
    _confirmFocusNode.addListener(() {
      if (_confirmFocusNode.hasFocus &&
          _stage == _Stage.password &&
          _passwordValid) {
        _advance(_Stage.confirm);
      }
    });
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint(
          '[phone-auth] modal.dispose → stage=$_stage busy=$_busy authFlow=$_authFlow pendingUserId=$_pendingUserId verificationIdSet=${_verificationId != null} errorMessage=${_errorMessage == null ? "null" : "\"${_errorMessage!.substring(0, _errorMessage!.length.clamp(0, 60))}\""}');
    }
    _lastNameRevealTimer?.cancel();
    _resendTicker?.cancel();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _relationshipOtherController.dispose();
    super.dispose();
  }

  // Debounced reveal / hide of the last-name field. Reveals after the user
  // pauses with ≥2 valid first-name chars; hides again if they clear
  // everything (signals that a first name is still required). We never
  // hide while the user has typed something into last name — that would
  // destroy in-progress input.
  void _updateLastNameVisibility() {
    final firstTrimmed = _firstNameController.text.trim();
    final lastHasContent = _lastNameController.text.isNotEmpty;

    final shouldReveal = !_lastNameRevealed &&
        firstTrimmed.length >= _lastNameRevealThreshold &&
        _isValidName(firstTrimmed);
    final shouldHide =
        _lastNameRevealed && firstTrimmed.isEmpty && !lastHasContent;

    _lastNameRevealTimer?.cancel();
    if (shouldReveal) {
      _lastNameRevealTimer = Timer(_lastNameRevealDelay, () {
        if (!mounted || _lastNameRevealed) return;
        setState(() => _lastNameRevealed = true);
      });
    } else if (shouldHide) {
      _lastNameRevealTimer = Timer(_lastNameRevealDelay, () {
        if (!mounted || !_lastNameRevealed) return;
        // Re-check inside the timer in case the user started typing again.
        if (_firstNameController.text.trim().isNotEmpty ||
            _lastNameController.text.isNotEmpty) {
          return;
        }
        setState(() => _lastNameRevealed = false);
      });
    }
  }

  bool get _showLastNameField =>
      _lastNameRevealed || _lastNameController.text.isNotEmpty;

  String get _studentName =>
      (_studentInfo?['studentFullName'] as String?) ?? 'your child';

  bool get _codeValid =>
      RegExp(r'^[A-Z0-9]{8}$').hasMatch(_codeController.text.toUpperCase());

  bool _isValidName(String v) =>
      RegExp(r"^[A-Za-zÀ-ÿ'\-\s]{1,}$").hasMatch(v.trim());
  bool get _firstValid => _isValidName(_firstNameController.text);
  bool get _lastValid => _isValidName(_lastNameController.text);

  // Relationship is valid once a preset is chosen, or "Other" is chosen with
  // non-empty free text. Resolves to the label stored on the parent doc.
  bool get _relationshipValid {
    final choice = _relationshipChoice;
    if (choice == null) return false;
    if (choice == GuardianRelationship.other) {
      return _relationshipOtherController.text.trim().isNotEmpty;
    }
    return true;
  }

  String? get _relationshipLabel {
    final choice = _relationshipChoice;
    if (choice == null) return null;
    if (choice == GuardianRelationship.other) {
      final text = _relationshipOtherController.text.trim();
      return text.isEmpty ? null : text;
    }
    return choice;
  }

  bool get _emailValid => RegExp(
        r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$',
      ).hasMatch(_emailController.text.trim());

  bool get _passwordValid {
    final v = _passwordController.text;
    return v.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(v) &&
        RegExp(r'[a-z]').hasMatch(v) &&
        RegExp(r'[0-9]').hasMatch(v);
  }

  bool get _confirmValid =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;

  // Australian mobile numbers only — 10 digits starting with 04. Spaces
  // are tolerated in the input for legibility but stripped for validation
  // and the E.164 conversion below.
  static final _auMobileRegex = RegExp(r'^04\d{8}$');

  String get _phoneDigits =>
      _phoneController.text.replaceAll(RegExp(r'\s+'), '');

  bool get _phoneValid => _auMobileRegex.hasMatch(_phoneDigits);

  /// Converts the Australian local form (`04XXXXXXXX`) to E.164 for Firebase.
  String get _phoneE164 => '+61${_phoneDigits.substring(1)}';

  bool get _smsCodeValid =>
      RegExp(r'^\d{6}$').hasMatch(_smsCodeController.text.trim());

  int get _resendRemainingSec {
    if (_lastSendAt == null) return 0;
    final remaining = _resendCooldown - DateTime.now().difference(_lastSendAt!);
    return remaining.isNegative ? 0 : remaining.inSeconds;
  }

  bool get _canResend => _resendRemainingSec == 0;

  void _startResendCountdown() {
    _lastSendAt = DateTime.now();
    _resendTicker?.cancel();
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendRemainingSec == 0) {
        t.cancel();
      }
      if (mounted) setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _openQrScanner() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LinkCodeScannerScreen(),
      ),
    );
    if (!mounted || scanned == null) return;
    _codeController.text = scanned;
    await _verifyCode();
  }

  Future<void> _verifyCode() async {
    if (!_codeValid) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final linkCode =
          await _linkingService.verifyCode(_codeController.text.toUpperCase());
      final metadata = linkCode.metadata ?? const {};
      if (metadata.isEmpty) {
        throw Exception(
          'Student information not found in code. Please ask your school to regenerate it.',
        );
      }
      if (!mounted) return;
      setState(() {
        _verifiedCode = linkCode;
        _studentInfo = metadata;
        _stage = _Stage.name;
      });
      AnalyticsService.instance.logParentCodeVerified();
    } on LinkingException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.userMessage);
      AnalyticsService.instance
          .logParentLinkingFailed(reason: e.runtimeType.toString());
    } on FirebaseException catch (e, st) {
      if (!mounted) return;
      final detail = e.code == 'unavailable'
          ? 'Can\'t reach the server right now. Please check your connection and try again.'
          : e.code == 'permission-denied'
              ? 'Permission denied reading student link codes. Please contact support.'
              : (e.message ?? 'Something went wrong. Please try again.');
      setState(() => _errorMessage = detail);
      AnalyticsService.instance.logParentLinkingFailed(reason: e.code);
      // `unavailable` is transient network noise, not a bug worth reporting.
      if (e.code != 'unavailable') {
        CrashReportingService.instance.recordError(
          e,
          st,
          reason: 'Parent code verification failed',
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      final detail = e.toString().replaceAll('Exception: ', '');
      setState(() => _errorMessage = detail);
      AnalyticsService.instance.logParentLinkingFailed(reason: detail);
      CrashReportingService.instance.recordError(
        e,
        st,
        reason: 'Parent code verification failed',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _advance(_Stage next) {
    setState(() {
      _errorMessage = null;
      _stage = next;
    });
  }

  void _goBack() {
    // Phone is now collected before email; sms back-step depends on whether
    // we took the phone-primary path (back to email) or the email/MFA path
    // (back to confirm). After the auth session is locked in (_pendingUserId
    // set, or phone primary verificationId issued) the user can't rewind
    // past phone — that would orphan the Firebase Auth state.
    final inEmailMfaFlow = _authFlow == _AuthFlow.emailMfa ||
        _authFlow == _AuthFlow.existingMfa;
    final prev = switch (_stage) {
      _Stage.code => _Stage.code,
      _Stage.name => _Stage.code,
      _Stage.relationship => _Stage.name,
      _Stage.phone => _Stage.relationship,
      _Stage.email =>
        _pendingUserId == null ? _Stage.phone : _Stage.email,
      _Stage.password => _Stage.email,
      _Stage.confirm => _Stage.password,
      _Stage.sms =>
        inEmailMfaFlow ? _Stage.confirm : _Stage.email,
      _Stage.success => _Stage.success,
    };
    setState(() {
      _errorMessage = null;
      _stage = prev;
    });
  }

  /// Phone stage → email stage. Fails fast if the phone is already
  /// registered (avoids paying for an SMS only to error later).
  Future<void> _advanceFromPhone() async {
    if (!_phoneValid) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final exists = await UserSchoolIndexService().phoneExists(_phoneE164);
      if (!mounted) return;
      if (exists) {
        setState(() => _errorMessage =
            'This phone number is already registered. Please log in instead.');
        return;
      }
      setState(() => _stage = _Stage.email);
    } catch (_) {
      // Don't block on a transient index read failure — let the user
      // continue and surface any real conflict at SMS-send time.
      if (mounted) setState(() => _stage = _Stage.email);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirm stage → SMS via the email + phone MFA flow. Creates the
  /// Firebase Auth account (or signs in to an existing one) then
  /// dispatches an SMS enrollment challenge.
  Future<void> _advanceFromConfirm() async {
    if (!_confirmValid) return;
    await _sendEnrollmentSms();
  }

  /// Routes the SMS-step "Resend" tap back through whichever sender
  /// dispatched the original code.
  Future<void> _resendSmsForCurrentFlow() {
    return switch (_authFlow) {
      _AuthFlow.phonePrimary => _sendPrimaryPhoneSms(),
      _AuthFlow.emailMfa => _sendEnrollmentSms(),
      _AuthFlow.existingMfa => _sendEnrollmentSms(),
      null => _sendEnrollmentSms(),
    };
  }

  /// Phone-primary path: dispatch a regular `verifyPhoneNumber` (no
  /// multi-factor session). The account is created on `_verifySmsAndFinish`
  /// via `signInWithCredential`.
  Future<void> _sendPrimaryPhoneSms() async {
    if (kDebugMode) {
      debugPrint(
          '[phone-auth] modal._sendPrimaryPhoneSms → entry phoneValid=$_phoneValid phone=$_phoneE164 emailEmpty=${_emailController.text.trim().isEmpty}');
    }
    if (!_phoneValid) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: _phoneE164,
        forceResendingToken: _resendToken,
        // Persist + warm-resume happens inside Firebase's codeSent
        // callback so we can survive an iOS reCAPTCHA modal disposal
        // mid-await. If the modal is gone by the time this fires,
        // navigate to the recovery screen via the global router hook.
        onCodeSentPersist: (h) {
          final code = _verifiedCode;
          if (code == null) return;
          final record = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: _phoneE164,
            mode: PhoneVerificationMode.phonePrimaryRegistration,
            contextJson: {
              'linkCodeId': code.id,
              'linkCodeValue': code.code,
              'schoolId': code.schoolId,
              'studentId': code.studentId,
              'studentFullName': _studentName,
              'fullName':
                  '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                      .trim(),
              'relationshipLabel': _relationshipLabel,
            },
            savedAt: DateTime.now(),
          );
          // Fire and forget — Hive write is queued synchronously even
          // though the Future itself is async, so the record is safe by
          // the time the next event loop tick happens.
          unawaited(PhoneVerificationRecoveryService.instance.save(record));
          if (!mounted) {
            if (kDebugMode) {
              debugPrint(
                  '[phone-auth] modal._sendPrimaryPhoneSms → codeSent fired but modal unmounted → triggering warm-resume navigation');
            }
            PhoneVerificationRecoveryService.instance.onRecoveryNeeded
                ?.call(record);
          }
        },
      );
      if (!mounted) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] modal._sendPrimaryPhoneSms → handle returned but widget unmounted; bailing');
        }
        return;
      }
      _startResendCountdown();
      setState(() {
        _authFlow = _AuthFlow.phonePrimary;
        _verificationId = handle.verificationId;
        _resendToken = handle.resendToken;
        _stage = _Stage.sms;
      });
      if (kDebugMode) {
        debugPrint(
            '[phone-auth] modal._sendPrimaryPhoneSms → success → stage=sms authFlow=phonePrimary');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] modal._sendPrimaryPhoneSms → FirebaseAuthException but widget unmounted; bailing code=${e.code}');
        }
        return;
      }
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
      if (kDebugMode) {
        debugPrint(
            '[phone-auth] modal._sendPrimaryPhoneSms → FirebaseAuthException code=${e.code} errorMessageSet=${_errorMessage?.substring(0, _errorMessage!.length.clamp(0, 80))}');
      }
    } catch (e, st) {
      if (!mounted) {
        if (kDebugMode) {
          debugPrint(
              '[phone-auth] modal._sendPrimaryPhoneSms → generic error but widget unmounted; bailing e=$e');
        }
        return;
      }
      setState(() => _errorMessage =
          'Could not send code: ${e.toString().replaceAll('Exception: ', '')}');
      if (kDebugMode) {
        debugPrint(
            '[phone-auth] modal._sendPrimaryPhoneSms → generic error e=$e');
      }
      CrashReportingService.instance
          .recordError(e, st, reason: 'Parent phone-primary SMS send failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Email + phone MFA path: create or sign-in the email user, then
  /// dispatch an enrollment SMS. Mirrors the previous `_sendPhoneCode`
  /// behaviour; just lifted out so the phone-primary path can sit next to it.
  Future<void> _sendEnrollmentSms() async {
    if (!_phoneValid) return;
    final code = _verifiedCode;
    if (code == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final phone = _phoneE164;

    try {
      // Resolve (create-or-signin) the user exactly once per flow. Subsequent
      // taps are resends and reuse the existing auth session.
      if (_pendingUserId == null) {
        try {
          final cred = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          await cred.user!.sendEmailVerification();
          _pendingUserId = cred.user!.uid;
          _mfaAlreadyEnrolled = false;
        } on FirebaseAuthException catch (e) {
          if (e.code == 'email-already-in-use') {
            // Existing account; try to sign in. If MFA is already enrolled,
            // Firebase throws FirebaseAuthMultiFactorException instead.
            try {
              final cred = await _auth.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
              _pendingUserId = cred.user!.uid;

              // Existing account without MFA — short-circuit "already linked
              // to this student" before we dispatch an SMS.
              final existing = await _firestore
                  .collection('schools')
                  .doc(code.schoolId)
                  .collection('parents')
                  .doc(cred.user!.uid)
                  .get();
              if (existing.exists &&
                  code.status == LinkCodeStatus.used &&
                  code.usedBy == cred.user!.uid) {
                await _auth.signOut();
                _pendingUserId = null;
                setState(() => _errorMessage =
                    'You are already registered and linked to this student. Please use the login page.');
                return;
              }

              _mfaAlreadyEnrolled =
                  await _smsService.hasPhoneFactor(cred.user!);
            } on FirebaseAuthMultiFactorException catch (mfaError) {
              // Existing account already has MFA — use the login resolver
              // flow instead. The user must verify with their existing
              // enrolled phone (not the one they just typed).
              _loginMfaResolver = mfaError.resolver;
              _mfaAlreadyEnrolled = true;
              final loginHandle = await _smsService.sendLoginCode(
                resolver: mfaError.resolver,
              );
              if (!mounted) return;
              setState(() {
                _authFlow = _AuthFlow.existingMfa;
                _verificationId = loginHandle.verificationId;
                _resendToken = loginHandle.resendToken;
                _stage = _Stage.sms;
              });
              return;
            } on FirebaseAuthException catch (signInError) {
              if (signInError.code == 'wrong-password' ||
                  signInError.code == 'invalid-credential') {
                setState(() => _errorMessage =
                    'This email is already registered with a different password. If this is your account, please log in instead.');
                return;
              }
              rethrow;
            }
          } else if (e.code == 'invalid-email' || e.code == 'weak-password') {
            setState(() {
              _errorMessage = _authErrorMessage(e.code);
              _stage =
                  e.code == 'weak-password' ? _Stage.password : _Stage.email;
            });
            return;
          } else {
            rethrow;
          }
        }
      }

      // At this point we have a signed-in user. If MFA is already enrolled,
      // bail — we would have already taken the login-resolver branch above.
      if (_mfaAlreadyEnrolled) {
        // Shouldn't be reached given the login branch returns early, but
        // guard against a programmer error.
        setState(() => _errorMessage =
            'Phone MFA already set up on this account. Please log in instead.');
        return;
      }

      // Primary phone verification (no multi-factor session): the phone is
      // verified + linked client-side, then enrolled server-side via
      // linkPhoneAndEnrollMfa. The client-side MFA-session enroll is blocked
      // until the email is verified, which we don't require during signup.
      final handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: phone,
        forceResendingToken: _resendToken,
        // Resilience: iOS can pop this modal during the reCAPTCHA Safari
        // handoff. Persist the verification + signup context so the recovery
        // screen can finish enrolment on the already-signed-in account.
        onCodeSentPersist: (h) {
          final record = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: phone,
            mode: PhoneVerificationMode.parentMfaEnrollment,
            contextJson: {
              'schoolId': code.schoolId,
              'linkCode': code.code,
              'email': email,
              'fullName':
                  '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                      .trim(),
              'relationshipLabel': _relationshipLabel,
            },
            savedAt: DateTime.now(),
          );
          unawaited(PhoneVerificationRecoveryService.instance.save(record));
          if (!mounted) {
            PhoneVerificationRecoveryService.instance.onRecoveryNeeded
                ?.call(record);
          }
        },
      );

      if (!mounted) return;
      _startResendCountdown();
      setState(() {
        _authFlow = _AuthFlow.emailMfa;
        _verificationId = handle.verificationId;
        _resendToken = handle.resendToken;
        _stage = _Stage.sms;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
      AnalyticsService.instance.logParentLinkingFailed(reason: e.code);
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not send code: ${e.toString().replaceAll('Exception: ', '')}');
      CrashReportingService.instance
          .recordError(e, st, reason: 'Parent SMS send failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Verifies the SMS code, either enrolling the phone factor (new / existing
  /// non-MFA account) or resolving the login (existing MFA account), then
  /// writes the parent doc and links the student.
  Future<void> _verifySmsAndFinish() async {
    if (!_smsCodeValid) return;
    final code = _verifiedCode;
    final verificationId = _verificationId;
    if (code == null || verificationId == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneE164;
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';
    final smsCode = _smsCodeController.text.trim();

    try {
      String userId;
      String? enrolledPhone;
      final isPhonePrimary = _authFlow == _AuthFlow.phonePrimary;
      final hasEmail = email.isNotEmpty;
      final resolver = _loginMfaResolver;

      if (isPhonePrimary) {
        // Phone-primary branch: signInWithCredential creates the account
        // (Firebase Auth uses the phone number as the credential).
        final cred = await _smsService.signInWithPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );
        userId = cred.user!.uid;
        enrolledPhone = phone;
      } else if (resolver != null) {
        // Existing-MFA branch: resolveSignIn completes the login; phone stays
        // whatever was previously enrolled.
        final cred = await _smsService.resolveLogin(
          resolver: resolver,
          verificationId: verificationId,
          smsCode: smsCode,
        );
        userId = cred.user!.uid;
        enrolledPhone = null; // not changing the enrolled phone
      } else {
        // Email + MFA branch: the server enrols the phone factor AND finalises
        // the signup (parent doc + indexes + child link) — because enrolling
        // MFA revokes the client session, so the client can't write afterwards.
        // It returns a custom token we re-auth with to land on home.
        final user = _auth.currentUser;
        if (user == null) {
          setState(() => _errorMessage =
              'Your session expired. Please start registration again.');
          return;
        }
        final outcome = await _smsService.completeMfaSignup(
          user: user,
          verificationId: verificationId,
          smsCode: smsCode,
          phoneNumber: phone,
          role: 'parent',
          schoolId: code.schoolId,
          fullName: fullName,
          email: hasEmail ? email : null,
          relationshipLabel: _relationshipLabel,
          linkCode: code.code,
        );
        unawaited(PhoneVerificationRecoveryService.instance.clear());
        if (!mounted) return;
        if (outcome == MfaSignupOutcome.needsLogin) {
          // Fully set up, but the session couldn't be re-established (MFA
          // challenge on the custom token) — send the user to log in.
          _goToLoginAfterSignup();
          return;
        }
        // sessionReady: the server wrote the parent doc — read it for the
        // success card, then show success. Server already did the rest.
        final parentSnap = await _firestore
            .collection('schools')
            .doc(code.schoolId)
            .collection('parents')
            .doc(user.uid)
            .get();
        setState(() {
          _createdParent =
              parentSnap.exists ? UserModel.fromFirestore(parentSnap) : null;
          _stage = _Stage.success;
        });
        AnalyticsService.instance.logParentLinkingCompleted();
        return;
      }

      final indexService = UserSchoolIndexService();
      final parentRef = _firestore
          .collection('schools')
          .doc(code.schoolId)
          .collection('parents')
          .doc(userId);
      final existingDoc = await parentRef.get();

      if (!existingDoc.exists) {
        final parentUser = UserModel(
          id: userId,
          email: hasEmail ? email : null,
          fullName: fullName,
          role: UserRole.parent,
          schoolId: code.schoolId,
          linkedChildren: const [],
          createdAt: DateTime.now(),
          isActive: true,
          phoneNumber: enrolledPhone,
          phoneVerified: true,
          relationshipLabel: _relationshipLabel,
        );
        await parentRef.set(parentUser.toFirestore());
        try {
          await _firestore
              .collection('schools')
              .doc(code.schoolId)
              .update({'parentCount': FieldValue.increment(1)});
        } catch (_) {
          // Non-critical; continue.
        }
      } else {
        // Existing parent doc — they already registered (e.g. re-entering to
        // link another child). The security rules only let a parent self-update
        // `relationshipLabel`; name/email/phone/phoneVerified are locked to
        // trusted writers (Admin SDK), so client-writing them here previously
        // failed with permission-denied. Leave the profile as first registered;
        // the linkParentToStudent callable below owns the new child link.
        if (_relationshipLabel != null) {
          await parentRef.update({'relationshipLabel': _relationshipLabel});
        }
      }

      // Index entries. Email index only when the parent supplied one;
      // phone index always (phone is now mandatory at registration).
      if (hasEmail) {
        await indexService.createOrUpdateIndex(
          email: email,
          schoolId: code.schoolId,
          userType: 'parent',
          userId: userId,
        );
      }
      if (enrolledPhone != null) {
        await indexService.createOrUpdatePhoneIndex(
          phoneE164: enrolledPhone,
          schoolId: code.schoolId,
          userType: 'parent',
          userId: userId,
        );
      }

      try {
        await _linkingService.linkParentToStudent(
          code: code.code,
          parentUserId: userId,
          parentEmail: hasEmail ? email : null,
        );
      } on AlreadyLinkedException {
        // Treat as success — already linked.
      }

      // Finished in-modal — drop any recovery record (phone-primary or MFA)
      // so a cold start doesn't resume an already-completed signup.
      unawaited(PhoneVerificationRecoveryService.instance.clear());

      final refreshed = await parentRef.get();
      if (!mounted) return;
      setState(() {
        _createdParent =
            refreshed.exists ? UserModel.fromFirestore(refreshed) : null;
        _stage = _Stage.success;
      });
      AnalyticsService.instance.logParentLinkingCompleted();
    } on LinkingException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.userMessage);
      AnalyticsService.instance
          .logParentLinkingFailed(reason: e.runtimeType.toString());
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
      AnalyticsService.instance.logParentLinkingFailed(reason: e.code);
    } catch (e, st) {
      if (!mounted) return;
      var detail = e.toString();
      if (detail.contains('permission-denied')) {
        detail =
            'Firestore permission denied. The security rules may need updating.';
      } else if (detail.contains('unavailable')) {
        detail = 'Firebase is temporarily unavailable. Check your connection.';
      }
      setState(() => _errorMessage = 'Registration error: $detail');
      AnalyticsService.instance.logParentLinkingFailed(reason: detail);
      CrashReportingService.instance
          .recordError(e, st, reason: 'Parent registration failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please log in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 8 characters.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  void _finishAndGoHome() {
    final parent = _createdParent;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    if (parent != null) {
      final route = AppRouter.getHomeRouteForRole(parent.role);
      router.go(route);
    }
  }

  /// Fallback for when the signup completed server-side but the custom-token
  /// re-auth was MFA-challenged: the account is fully set up, so close the modal
  /// and send the user to log in (phone or email + SMS) to continue.
  void _goToLoginAfterSignup() {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/auth/login');
    messenger.showSnackBar(const SnackBar(
      content: Text('Account created! Please log in to continue.'),
    ));
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final maxCardHeight = media.size.height * 0.82;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 24 + media.viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxCardHeight),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(anim);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _stage == _Stage.success
                ? _SuccessCard(
                    key: const ValueKey('success'),
                    studentName: _studentName,
                    onStart: _finishAndGoHome,
                  )
                : KeyedSubtree(
                    key: const ValueKey('form'),
                    // AutofillGroup + per-field autofillHints stabilise iOS
                    // credential AutoFill so the "Passwords" accessory bar
                    // doesn't flicker — that flicker changed the keyboard inset,
                    // shifted the modal, and dropped the field's focus.
                    child: AutofillGroup(child: _buildFormCard()),
                  ),
          ),
        ),
      ),
    )
        .animate()
        .slideY(
          begin: 1.0,
          end: 0.0,
          duration: 450.ms,
          curve: Curves.easeOutCubic,
        )
        .fadeIn(duration: 300.ms);
  }

  Widget _buildFormCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: LumiTokens.ink.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                ..._buildCompletedChips(),
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 12),
                ],
                _buildActiveInput(),
                const SizedBox(height: 20),
                _buildPrimaryAction(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final canBack = _stage != _Stage.code && !_busy;
    final title = switch (_stage) {
      _Stage.code => 'Link your child',
      _Stage.name => 'Your name',
      _Stage.relationship => 'Your relationship',
      _Stage.email => 'Email address',
      _Stage.password => 'Create password',
      _Stage.confirm => 'Confirm password',
      _Stage.phone => 'Phone number',
      _Stage.sms => 'Enter SMS code',
      _Stage.success => '',
    };

    return Row(
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: canBack
              ? IconButton(
                  onPressed: _goBack,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  color: LumiTokens.ink,
                  splashRadius: 18,
                )
              : null,
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: LumiTextStyles.h3(),
          ),
        ),
        SizedBox(
          width: 40,
          height: 40,
          child: IconButton(
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 22),
            color: LumiTokens.ink,
            splashRadius: 18,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCompletedChips() {
    final chips = <Widget>[];
    final emailEntered = _emailController.text.trim().isNotEmpty;

    if (_stage.index >= _Stage.name.index) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_connected'),
        label: 'Connected to $_studentName',
      ));
    }
    if (_stage.index >= _Stage.relationship.index) {
      final name =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();
      chips.add(_CompletedChip(
        key: const ValueKey('chip_name'),
        label: name,
      ));
    }
    if (_stage.index >= _Stage.phone.index && _relationshipLabel != null) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_relationship'),
        label: 'Relationship: ${_relationshipLabel!}',
      ));
    }
    if (_stage.index >= _Stage.email.index) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_phone'),
        label: _loginMfaResolver != null
            ? 'Verifying existing phone'
            : 'Phone: $_phoneDigits',
      ));
    }
    if (_stage.index >= _Stage.password.index && emailEntered) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_email'),
        label: _emailController.text.trim(),
      ));
    }
    if (_stage.index >= _Stage.confirm.index && emailEntered) {
      chips.add(const _CompletedChip(
        key: ValueKey('chip_password'),
        label: 'Password set',
      ));
    }
    if (_stage.index >= _Stage.sms.index && emailEntered) {
      chips.add(const _CompletedChip(
        key: ValueKey('chip_password_confirmed'),
        label: 'Password confirmed',
      ));
    }

    if (chips.isEmpty) return const [];
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final chip in chips) ...[
            chip,
            const SizedBox(height: 8),
          ],
        ],
      ),
      const SizedBox(height: 4),
    ];
  }

  Widget _buildActiveInput() {
    // Pure fade — the parent card's AnimatedSize handles height changes.
    // A nested SizeTransition here fights that animator and causes a jitter
    // as the email peek compacts into its chip during stage transitions.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: KeyedSubtree(
        key: ValueKey(_stage),
        child: switch (_stage) {
          _Stage.code => _buildCodeInput(),
          _Stage.name => _buildNameInputs(),
          _Stage.relationship => _buildRelationshipInput(),
          _Stage.email => _buildEmailInput(),
          _Stage.password => _buildPasswordInput(),
          _Stage.confirm => _buildConfirmInput(),
          _Stage.phone => _buildPhoneInput(),
          _Stage.sms => _buildSmsInput(),
          _Stage.success => const SizedBox.shrink(),
        },
      ),
    );
  }

  Widget _buildCodeInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 8-character code from your child\'s school.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _codeController,
          hintText: 'e.g. ABC12345',
          autofocus: true,
          maxLength: 8,
          textInputAction: TextInputAction.done,
          prefixIcon: IconButton(
            onPressed: _busy ? null : _openQrScanner,
            tooltip: 'Scan QR code',
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            color: LumiTokens.ink,
            splashRadius: 18,
          ),
          inputFormatters: [
            _UpperCaseFormatter(),
          ],
        ),
      ],
    );
  }

  Widget _buildNameInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _firstNameController,
          hintText: 'First name',
          autofocus: true,
          textInputAction: TextInputAction.next,
          errorText: _firstNameController.text.isNotEmpty && !_firstValid
              ? 'Enter a valid first name'
              : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _showLastNameField
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LumiInput(
                    accentColor: LumiTokens.red,
                    controller: _lastNameController,
                    hintText: 'Last name',
                    textInputAction: TextInputAction.done,
                    errorText:
                        _lastNameController.text.isNotEmpty && !_lastValid
                            ? 'Enter a valid last name'
                            : null,
                  )
                      .animate()
                      .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 260.ms,
                        curve: Curves.easeOutCubic,
                      ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRelationshipInput() {
    final options = [
      ...GuardianRelationship.presets,
      GuardianRelationship.other,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How are you related to $_studentName? This appears on reading logs you record.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option),
                selected: _relationshipChoice == option,
                selectedColor: LumiTokens.red.withValues(alpha: 0.2),
                onSelected: (_) => setState(() => _relationshipChoice = option),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _relationshipChoice == GuardianRelationship.other
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LumiInput(
                    accentColor: LumiTokens.red,
                    controller: _relationshipOtherController,
                    hintText: 'e.g. Aunt, Foster carer',
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                  )
                      .animate()
                      .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 260.ms,
                        curve: Curves.easeOutCubic,
                      ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    // Email is OPTIONAL: phone is the mandatory identifier. We still
    // recommend an email because it's the only password-reset path. Without
    // one the parent will sign in via SMS every time.
    //
    // Progressive reveal: once a valid email is typed, show the password
    // field below it without compacting the email. The stage only advances
    // when the user actually taps into the password field (focus listener).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recommended. We\'ll use this to reset your password if you forget it. Without an email, you\'ll sign in with an SMS code each time.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _emailController,
          hintText: 'you@example.com',
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          errorText: _emailController.text.isNotEmpty && !_emailValid
              ? 'Enter a valid email address'
              : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _emailValid
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LumiPasswordInput(
                    accentColor: LumiTokens.red,
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    autofillHints: const [AutofillHints.newPassword],
                    hintText: 'Password (at least 8 characters)',
                  )
                      .animate()
                      .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 260.ms,
                        curve: Curves.easeOutCubic,
                      ),
                )
              : const SizedBox.shrink(),
        ),
        // Subtle escape hatch for carers who genuinely don't have an email.
        // Worded so users with an email don't feel invited to skip — the
        // copy implies "you don't have one" rather than "skip this step".
        if (_emailController.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: _busy ? null : _sendPrimaryPhoneSms,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'I don\'t have an email',
                  style: LumiTextStyles.bodySmall(
                    color: LumiTokens.ink.withValues(alpha: 0.55),
                  ).copyWith(decoration: TextDecoration.underline),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPasswordInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiPasswordInput(
          accentColor: LumiTokens.red,
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          autofocus: true,
          autofillHints: const [AutofillHints.newPassword],
          hintText: 'At least 8 characters',
          helperText: 'Include uppercase, lowercase, and a number.',
          errorText: _passwordController.text.isNotEmpty && !_passwordValid
              ? 'Must be 8+ chars with upper, lower, and a number'
              : null,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _passwordValid
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: LumiPasswordInput(
                    accentColor: LumiTokens.red,
                    controller: _confirmController,
                    focusNode: _confirmFocusNode,
                    autofillHints: const [AutofillHints.newPassword],
                    hintText: 'Confirm password',
                  )
                      .animate()
                      .fadeIn(duration: 220.ms, curve: Curves.easeOut)
                      .slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 260.ms,
                        curve: Curves.easeOutCubic,
                      ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildConfirmInput() {
    return LumiPasswordInput(
      accentColor: LumiTokens.red,
      controller: _confirmController,
      focusNode: _confirmFocusNode,
      autofocus: true,
      autofillHints: const [AutofillHints.newPassword],
      hintText: 'Re-enter password',
      errorText: _confirmController.text.isNotEmpty && !_confirmValid
          ? 'Passwords don\'t match'
          : null,
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'We\'ll text you a code to confirm your mobile. This is how you\'ll sign in.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _phoneController,
          hintText: '0400 000 000',
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          helperText: 'Australian mobile only.',
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
          ],
          errorText: _phoneDigits.isNotEmpty && !_phoneValid
              ? 'Enter a 10-digit Australian mobile starting with 04'
              : null,
        ),
      ],
    );
  }

  Widget _buildSmsInput() {
    final subtitle = _loginMfaResolver != null
        ? 'We sent a code to the phone already on this account.'
        : 'Enter the 6-digit code sent to $_phoneDigits.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          subtitle,
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _smsCodeController,
          hintText: '123456',
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textInputAction: TextInputAction.done,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (_) {
            if (_smsCodeValid && !_busy) {
              _verifySmsAndFinish();
            }
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy || !_canResend ? null : _resendSmsForCurrentFlow,
            child: Text(
              _canResend ? 'Resend code' : 'Resend in ${_resendRemainingSec}s',
              style: LumiTextStyles.bodySmall(color: LumiTokens.red),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryAction() {
    final (label, enabled, onPressed) = switch (_stage) {
      _Stage.code => (
          'Verify code',
          _codeValid && !_busy,
          _verifyCode,
        ),
      _Stage.name => (
          'Next',
          _firstValid && _lastValid,
          () => _advance(_Stage.relationship),
        ),
      _Stage.relationship => (
          'Next',
          _relationshipValid,
          () => _advance(_Stage.phone),
        ),
      _Stage.phone => (
          'Next',
          _phoneValid && !_busy,
          _advanceFromPhone,
        ),
      // Primary "Next" requires a valid email — the "I don't have an email"
      // text link below the input handles the skip path. This keeps the
      // primary CTA pointing at the recommended flow.
      _Stage.email => (
          'Next',
          _emailValid && !_busy,
          () => _advance(_Stage.password),
        ),
      _Stage.password => (
          'Next',
          _passwordValid,
          () => _advance(_Stage.confirm),
        ),
      _Stage.confirm => (
          'Send verification code',
          _confirmValid && !_busy,
          _advanceFromConfirm,
        ),
      _Stage.sms => (
          _loginMfaResolver != null
              ? 'Verify & Link Child'
              : 'Verify & Create Account',
          _smsCodeValid && !_busy,
          _verifySmsAndFinish,
        ),
      _Stage.success => ('', false, () {}),
    };

    return LumiPrimaryButton(
      color: LumiTokens.red,
      onPressed: enabled ? onPressed : null,
      text: label,
      isLoading: _busy,
      isFullWidth: true,
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _CompletedChip extends StatelessWidget {
  final String label;
  const _CompletedChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.tintGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: LumiTokens.green.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: LumiTokens.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: LumiTextStyles.bodySmall(color: LumiTokens.green)
                  .copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 260.ms, curve: Curves.easeOut).slideY(
        begin: 0.3, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: LumiTokens.red.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: LumiTokens.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: LumiTextStyles.bodySmall(color: LumiTokens.red),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).shake(duration: 300.ms, hz: 3);
  }
}

class _SuccessCard extends StatelessWidget {
  final String studentName;
  final VoidCallback onStart;

  const _SuccessCard({
    super.key,
    required this.studentName,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: LumiTokens.ink.withValues(alpha: 0.18),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: LumiTokens.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 42,
                  color: LumiTokens.green,
                ),
              )
                  .animate()
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1, 1),
                    duration: 450.ms,
                    curve: Curves.elasticOut,
                  )
                  .fadeIn(duration: 250.ms),
            ),
            const SizedBox(height: 16),
            Text(
              'You\'re all set!',
              textAlign: TextAlign.center,
              style: LumiTextStyles.h2(),
            ),
            const SizedBox(height: 8),
            Text(
              'Your account is linked to $studentName. Let\'s start reading together.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.body(
                color: LumiTokens.ink.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            LumiPrimaryButton(
              color: LumiTokens.red,
              onPressed: onStart,
              text: 'Start Reading',
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
