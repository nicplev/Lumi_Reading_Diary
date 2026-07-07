import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../data/models/user_model.dart';
import '../../../services/crash_reporting_service.dart';
import '../../../services/phone_verification_recovery_service.dart';
import '../../../services/school_code_service.dart';
import '../../../services/sms_verification_service.dart';

/// Opens the floating teacher registration modal over the current screen.
/// Blurs the background, rises from the bottom, and walks the user through
/// school code verification → name → email → password → confirm → success
/// (pending admin approval). Mirrors the parent registration modal.
Future<void> showTeacherRegistrationModal(BuildContext context) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      barrierDismissible: false,
      barrierLabel: 'Teacher registration',
      transitionDuration: const Duration(milliseconds: 850),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => const _TeacherRegistrationOverlay(),
    ),
  );
}

const double _kMaxBlur = 18;
const double _kMaxDim = 0.18;

enum _Stage { code, name, email, password, confirm, phone, sms, success }

class _TeacherRegistrationOverlay extends StatelessWidget {
  const _TeacherRegistrationOverlay();

  @override
  Widget build(BuildContext context) {
    final animation =
        ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final raw = animation.value.clamp(0.0, 1.0);
                  final blurT = Curves.easeInCubic.transform(raw);
                  final dimT = Curves.easeInOutCubic.transform(raw);
                  return BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: _kMaxBlur * blurT,
                      sigmaY: _kMaxBlur * blurT,
                    ),
                    child: Container(
                      color: Colors.black.withValues(alpha: _kMaxDim * dimT),
                    ),
                  );
                },
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final isReversing =
                    animation.status == AnimationStatus.reverse ||
                        animation.status == AnimationStatus.dismissed;
                final raw = animation.value.clamp(0.0, 1.0);
                final slideT = isReversing
                    ? Curves.easeInCubic.transform(1 - raw)
                    : 0.0;
                final opacity = isReversing ? raw : 1.0;
                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, slideT * 220),
                    child: child,
                  ),
                );
              },
              child: const _TeacherRegistrationCard(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherRegistrationCard extends StatefulWidget {
  const _TeacherRegistrationCard();

  @override
  State<_TeacherRegistrationCard> createState() =>
      _TeacherRegistrationCardState();
}

class _TeacherRegistrationCardState extends State<_TeacherRegistrationCard> {
  final _schoolCodeService = SchoolCodeService();
  final _smsService = SmsVerificationService();
  final _auth = FirebaseAuth.instance;

  final _codeController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();

  _Stage _stage = _Stage.code;
  bool _busy = false;
  String? _errorMessage;

  String? _verifiedSchoolId;
  String? _verifiedSchoolName;
  String? _verifiedCodeId;
  // The raw school code the teacher entered. Passed to signup finalisation so
  // the server DERIVES + validates schoolId from it, rather than trusting the
  // client-supplied _verifiedSchoolId (1.3).
  String? _verifiedSchoolCode;
  UserModel? _createdTeacher;

  // SMS MFA state — once the auth user is created we must not recreate it
  // on retry, so [_pendingUserId] pins the in-progress registration. The
  // verification id is refreshed on every resend.
  String? _pendingUserId;
  String? _verificationId;
  int? _resendToken;
  DateTime? _lastSendAt;
  Timer? _resendTicker;
  static const _resendCooldown = Duration(seconds: 30);

  bool _lastNameRevealed = false;
  Timer? _lastNameRevealTimer;
  static const _lastNameRevealThreshold = 2;
  static const _lastNameRevealDelay = Duration(milliseconds: 300);

  // Persistent focus nodes — shared across stage builds so focus survives the
  // AnimatedSwitcher transition when a stage advance mounts the next field.
  // `autofocus` is a no-op mid-transition (the outgoing field still holds
  // focus), so `_focusStageField` hands focus over explicitly instead.
  final _codeFocusNode = FocusNode();
  final _firstNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  final _smsFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmFocusNode = FocusNode();
  // Dedicated nodes for the progressive-reveal "peek" fields (the password
  // shown under a valid email, the confirm shown under a valid password).
  // They must NOT reuse the same-field node from the next stage: during the
  // AnimatedSwitcher cross-fade both instances mount at once, so a shared node
  // is attached twice and the outgoing peek's disposal rips focus off the
  // freshly-focused field — dropping the keyboard.
  final _passwordPeekFocusNode = FocusNode();
  final _confirmPeekFocusNode = FocusNode();

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
    ]) {
      c.addListener(() => setState(() {}));
    }
    _firstNameController.addListener(_updateLastNameVisibility);
    _lastNameController.addListener(_updateLastNameVisibility);
    // Progressive reveal: when the user taps into the revealed "peek" field,
    // commit the stage advance so the previous field compacts to a chip.
    _passwordPeekFocusNode.addListener(() {
      if (_passwordPeekFocusNode.hasFocus &&
          _stage == _Stage.email &&
          _emailValid) {
        _advance(_Stage.password);
      }
    });
    _confirmPeekFocusNode.addListener(() {
      if (_confirmPeekFocusNode.hasFocus &&
          _stage == _Stage.password &&
          _passwordValid) {
        _advance(_Stage.confirm);
      }
    });
  }

  @override
  void dispose() {
    _lastNameRevealTimer?.cancel();
    _resendTicker?.cancel();
    _codeFocusNode.dispose();
    _firstNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _phoneFocusNode.dispose();
    _smsFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    _passwordPeekFocusNode.dispose();
    _confirmPeekFocusNode.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    super.dispose();
  }

  // Debounced reveal / hide of the last-name field. Reveals after the user
  // pauses with ≥2 valid first-name chars; hides again if they clear
  // everything. Never hides while last name has content.
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

  bool get _codeValid => _codeController.text.trim().length >= 6;

  bool _isValidName(String v) =>
      RegExp(r"^[A-Za-zÀ-ÿ'\-\s]{1,}$").hasMatch(v.trim());
  bool get _firstValid => _isValidName(_firstNameController.text);
  bool get _lastValid => _isValidName(_lastNameController.text);

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

  /// Converts the Australian local form (`04XXXXXXXX`) to E.164 for Firebase
  /// by dropping the leading zero and prefixing `+61`.
  String get _phoneE164 => '+61${_phoneDigits.substring(1)}';

  bool get _smsCodeValid =>
      RegExp(r'^\d{6}$').hasMatch(_smsCodeController.text.trim());

  int get _resendRemainingSec {
    if (_lastSendAt == null) return 0;
    final remaining =
        _resendCooldown - DateTime.now().difference(_lastSendAt!);
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

  Future<void> _verifyCode() async {
    if (!_codeValid) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final details =
          await _schoolCodeService.validateSchoolCode(_codeController.text);
      if (!mounted) return;
      setState(() {
        _verifiedSchoolId = details['schoolId'];
        _verifiedSchoolName = details['schoolName'];
        _verifiedCodeId = details['codeId'];
        _verifiedSchoolCode = _codeController.text.trim().toUpperCase();
        _stage = _Stage.name;
      });
      _focusStageField(_Stage.name);
    } on SchoolCodeException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } on FirebaseException catch (e, st) {
      if (!mounted) return;
      final detail = e.code == 'unavailable'
          ? 'Can\'t reach the server right now. Please check your connection and try again.'
          : e.code == 'permission-denied'
              ? 'Permission denied reading school codes. Please contact support.'
              : (e.message ?? 'Something went wrong. Please try again.');
      setState(() => _errorMessage = detail);
      // `unavailable` is transient network noise, not a bug worth reporting.
      if (e.code != 'unavailable') {
        CrashReportingService.instance.recordError(
          e,
          st,
          reason: 'Teacher school code verification failed',
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      final detail = e.toString().replaceAll('Exception: ', '');
      setState(() => _errorMessage = detail);
      CrashReportingService.instance.recordError(
        e,
        st,
        reason: 'Teacher school code verification failed',
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
    _focusStageField(next);
  }

  /// Hands keyboard focus to the incoming stage's primary field after the
  /// frame that mounts it. Driven explicitly rather than via `autofocus`
  /// because a stage change fired by the "Next" button leaves the *outgoing*
  /// field focused while the AnimatedSwitcher cross-fades — so the incoming
  /// field's `autofocus` is skipped and the keyboard visibly drops.
  void _focusStageField(_Stage stage) {
    final node = switch (stage) {
      _Stage.code => _codeFocusNode,
      _Stage.name => _firstNameFocusNode,
      _Stage.email => _emailFocusNode,
      _Stage.password => _passwordFocusNode,
      _Stage.confirm => _confirmFocusNode,
      _Stage.phone => _phoneFocusNode,
      _Stage.sms => _smsFocusNode,
      _Stage.success => null,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (node != null) {
        node.requestFocus();
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _goBack() {
    final prev = switch (_stage) {
      _Stage.code => _Stage.code,
      _Stage.name => _Stage.code,
      _Stage.email => _Stage.name,
      _Stage.password => _Stage.email,
      _Stage.confirm => _Stage.password,
      // Once the auth user exists we can't rewind to the password stage without
      // leaking an orphaned Firebase Auth record. The primary button itself is
      // gated on _pendingUserId == null at those steps.
      _Stage.phone => _pendingUserId == null ? _Stage.confirm : _Stage.phone,
      _Stage.sms => _Stage.phone,
      _Stage.success => _Stage.success,
    };
    setState(() {
      _errorMessage = null;
      _stage = prev;
    });
    _focusStageField(prev);
  }

  /// Creates the Firebase Auth user (first press) and dispatches an SMS
  /// enrollment code. Re-pressing resends without recreating the account —
  /// resends consult [_pendingUserId] to avoid `email-already-in-use` loops.
  Future<void> _sendPhoneCode() async {
    if (!_phoneValid) return;
    if (_verifiedSchoolId == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();
    final phone = _phoneE164;

    try {
      if (_pendingUserId == null) {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = cred.user!;
        await user.updateDisplayName(fullName);
        await user.sendEmailVerification();
        _pendingUserId = user.uid;
      }
      // Mid-flow retries (resend from the SMS stage) just re-send the code;
      // the account already exists and the signed-in session is still ours.

      // Primary phone verification (no multi-factor session): the phone is
      // verified + linked client-side, then enrolled server-side via
      // linkPhoneAndEnrollMfa. The client-side MFA-session enroll is blocked
      // until the email is verified, which we don't require during signup.
      final handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: phone,
        forceResendingToken: _resendToken,
        // Resilience: iOS can pop this modal during the reCAPTCHA Safari
        // handoff (when silent-push app verification isn't available, e.g. the
        // Simulator). Persist the verification + signup context so the recovery
        // screen can finish enrolment. The created account stays signed in, so
        // recovery links + enrols the phone there instead of re-creating it.
        onCodeSentPersist: (h) {
          final record = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: phone,
            mode: PhoneVerificationMode.teacherMfaEnrollment,
            contextJson: {
              'schoolId': _verifiedSchoolId,
              'email': email,
              'fullName': fullName,
              'codeId': _verifiedCodeId,
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
        _verificationId = handle.verificationId;
        _resendToken = handle.resendToken;
        _stage = _Stage.sms;
      });
      _focusStageField(_Stage.sms);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      // `email-already-in-use` / weak password surface before we ever touch
      // phone auth — route the user back to the relevant stage with the
      // right message instead of leaving them stuck on the phone screen.
      if (e.code == 'email-already-in-use' ||
          e.code == 'invalid-email' ||
          e.code == 'weak-password') {
        final target =
            e.code == 'weak-password' ? _Stage.password : _Stage.email;
        setState(() {
          _errorMessage = _authErrorMessage(e.code);
          _stage = target;
        });
        _focusStageField(target);
      } else {
        setState(
            () => _errorMessage = SmsVerificationService.friendlyError(e));
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not send code: ${e.toString().replaceAll('Exception: ', '')}');
      CrashReportingService.instance
          .recordError(e, st, reason: 'Teacher SMS send failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Verifies the SMS code, enrolls the phone factor, writes the teacher
  /// Firestore document, and transitions to the success screen.
  Future<void> _verifySmsAndFinish() async {
    if (!_smsCodeValid) return;
    final schoolId = _verifiedSchoolId;
    final verificationId = _verificationId;
    if (schoolId == null || verificationId == null) return;

    final user = _auth.currentUser;
    if (user == null) {
      setState(() =>
          _errorMessage = 'Your session expired. Please start registration again.');
      return;
    }

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneE164;
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();

    try {
      final outcome = await _smsService.completeMfaSignup(
        user: user,
        verificationId: verificationId,
        smsCode: _smsCodeController.text.trim(),
        phoneNumber: phone,
        role: 'teacher',
        schoolId: schoolId,
        schoolCode: _verifiedSchoolCode,
        fullName: fullName,
        email: email,
      );

      // The server enrolled the factor AND wrote the teacher doc + index — the
      // enrol revokes the client session, so finalisation must be server-side.
      // Drop any recovery record so a cold start doesn't resume a done signup.
      unawaited(PhoneVerificationRecoveryService.instance.clear());

      if (!mounted) return;
      if (outcome == MfaSignupOutcome.needsLogin) {
        // Fully set up, but the session couldn't be re-established (MFA
        // challenge on the custom token) — send the user to log in.
        _goToLoginAfterSignup();
        return;
      }
      setState(() {
        _createdTeacher = UserModel(
          id: user.uid,
          email: email,
          fullName: fullName,
          role: UserRole.teacher,
          schoolId: schoolId,
          phoneNumber: phone,
          phoneVerified: true,
          createdAt: DateTime.now(),
          lastLoginAt: DateTime.now(),
        );
        _stage = _Stage.success;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
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
      CrashReportingService.instance
          .recordError(e, st, reason: 'Teacher registration failed');
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
    final teacher = _createdTeacher;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    if (teacher != null) {
      final route = AppRouter.getHomeRouteForRole(teacher.role);
      router.go(route, extra: teacher);
    }
  }

  /// Fallback for when the signup completed server-side but the custom-token
  /// re-auth was MFA-challenged: the account is fully set up, so close the modal
  /// and send the user to log in (email + password + SMS) to continue.
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

    return PopScope(
      // Lock the route while busy so a stray backdrop tap during the
      // reCAPTCHA→SMS gap can't dispose the modal mid-verify, and guard an
      // accidental abandon once the auth account exists but signup isn't
      // finalised (re-registering would then hit `email-already-in-use`).
      canPop: !_busy && (_pendingUserId == null || _stage == _Stage.success),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy) return;
        final navigator = Navigator.of(context);
        final leave = await _confirmAbandon();
        if (leave && mounted) navigator.pop();
      },
      child: SafeArea(
      top: false,
      child: Padding(
        // NB: no `media.viewInsets.bottom` — the overlay Scaffold already has
        // `resizeToAvoidBottomInset: true`, so adding it again double-lifted
        // the card off the keyboard.
        padding: const EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 24,
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
                    schoolName: _verifiedSchoolName ?? 'your school',
                    onDone: _finishAndGoHome,
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
        .fadeIn(duration: 300.ms),
    );
  }

  /// Confirms an intentional abandon after the account exists but signup is
  /// unfinished. Returns true only if the user explicitly chooses to leave.
  Future<bool> _confirmAbandon() async {
    // No account created yet → nothing to orphan, let the pop through.
    if (_pendingUserId == null || _stage == _Stage.success) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Finish setting up?', style: LumiTextStyles.h3()),
        content: Text(
          "Your account was created but setup isn't finished. If you leave now "
          "you'll need to log in with this email and password to complete it — "
          "signing up again will say the email is already in use.",
          style: LumiTextStyles.body(color: LumiTokens.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep going',
                style: LumiTextStyles.button(color: LumiTokens.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Leave',
                style: LumiTextStyles.button(color: LumiTokens.muted)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Widget _buildFormCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Container(
        clipBehavior: Clip.antiAlias,
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
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Scrollable content: grows with the accumulating chips and
                // scrolls once it outgrows the height cap. Kept separate from
                // the footer so the button below is always reachable.
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
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
                        ],
                      ),
                    ),
                  ),
                ),
                // Pinned footer: the primary action (and its loading spinner)
                // never scrolls out of view on the tall later stages.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: _buildPrimaryAction(),
                ),
              ],
            ),
            // Blocking busy overlay: an always-visible spinner plus a
            // tap-swallowing scrim over the reCAPTCHA→SMS gap.
            if (_busy)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: _buildBusyScrim(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Contextual label under the busy spinner so the wait reads as progress.
  String get _busyLabel => switch (_stage) {
        _Stage.code => 'Verifying school code…',
        _Stage.phone => 'Sending code…',
        _Stage.sms => 'Verifying…',
        _ => 'Please wait…',
      };

  Widget _buildBusyScrim() {
    return Container(
      color: LumiTokens.paper.withValues(alpha: 0.82),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(LumiTokens.red),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _busyLabel,
            textAlign: TextAlign.center,
            style: LumiTextStyles.bodySmall(
              color: LumiTokens.ink.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final canBack = _stage != _Stage.code && !_busy;
    final title = switch (_stage) {
      _Stage.code => 'Join your school',
      _Stage.name => 'Your name',
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

    if (_stage.index >= _Stage.name.index) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_school'),
        label: 'School verified: ${_verifiedSchoolName ?? ''}',
      ));
    }
    if (_stage.index >= _Stage.email.index) {
      final name =
          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
              .trim();
      chips.add(_CompletedChip(
        key: const ValueKey('chip_name'),
        label: name,
      ));
    }
    if (_stage.index >= _Stage.password.index) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_email'),
        label: _emailController.text.trim(),
      ));
    }
    if (_stage.index >= _Stage.confirm.index) {
      chips.add(const _CompletedChip(
        key: ValueKey('chip_password'),
        label: 'Password set',
      ));
    }
    if (_stage.index >= _Stage.phone.index) {
      chips.add(const _CompletedChip(
        key: ValueKey('chip_password_confirmed'),
        label: 'Password confirmed',
      ));
    }
    if (_stage.index >= _Stage.sms.index) {
      chips.add(_CompletedChip(
        key: const ValueKey('chip_phone'),
        label: 'Phone: $_phoneDigits',
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
          'Enter the school code from your school admin.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _codeController,
          focusNode: _codeFocusNode,
          hintText: 'e.g. LUMI2024',
          autofocus: true,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.characters,
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
          focusNode: _firstNameFocusNode,
          hintText: 'First name',
          textInputAction: TextInputAction.next,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.givenName],
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
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.familyName],
                    errorText: _lastNameController.text.isNotEmpty &&
                            !_lastValid
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

  Widget _buildEmailInput() {
    // Progressive reveal: once the email is valid, show the password field
    // below it without compacting the email. The stage only advances when the
    // user actually taps into the password field (focus listener fires).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _emailController,
          focusNode: _emailFocusNode,
          hintText: 'you@example.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
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
                    focusNode: _passwordPeekFocusNode,
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
                    focusNode: _confirmPeekFocusNode,
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
          'We\'ll text you a code to confirm your mobile. This becomes your sign-in second factor.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _phoneController,
          focusNode: _phoneFocusNode,
          hintText: '0400 000 000',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.telephoneNumber],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Enter the 6-digit code sent to $_phoneDigits.',
          style: LumiTextStyles.bodySmall(
            color: LumiTokens.ink.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          accentColor: LumiTokens.red,
          controller: _smsCodeController,
          focusNode: _smsFocusNode,
          hintText: '123456',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          // Lets iOS surface the incoming SMS code as a one-tap QuickType
          // suggestion above the keyboard.
          autofillHints: const [AutofillHints.oneTimeCode],
          // Cap at 6 without the "0/6" counter badge.
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          onChanged: (_) {
            // Auto-submit once the full 6-digit code is in — most SMS UX
            // flows do this so the user doesn't hunt for the verify button.
            if (_smsCodeValid && !_busy) {
              _verifySmsAndFinish();
            }
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy || !_canResend ? null : _sendPhoneCode,
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
          () => _advance(_Stage.email),
        ),
      _Stage.email => (
          'Next',
          _emailValid,
          () => _advance(_Stage.password),
        ),
      _Stage.password => (
          'Next',
          _passwordValid,
          () => _advance(_Stage.confirm),
        ),
      _Stage.confirm => (
          'Next',
          _confirmValid && !_busy,
          () => _advance(_Stage.phone),
        ),
      _Stage.phone => (
          _pendingUserId == null
              ? 'Send code'
              : _canResend
                  ? 'Resend code'
                  : 'Resend in ${_resendRemainingSec}s',
          _phoneValid && !_busy && (_pendingUserId == null || _canResend),
          _sendPhoneCode,
        ),
      _Stage.sms => (
          'Verify & Create Account',
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
    )
        .animate()
        .fadeIn(duration: 260.ms, curve: Curves.easeOut)
        .slideY(begin: 0.3, end: 0, duration: 320.ms, curve: Curves.easeOutCubic);
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
  final String schoolName;
  final VoidCallback onDone;

  const _SuccessCard({
    super.key,
    required this.schoolName,
    required this.onDone,
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
              'Welcome to $schoolName. Let\'s get your classes set up.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.body(
                color: LumiTokens.ink.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            LumiPrimaryButton(
              color: LumiTokens.red,
              onPressed: onDone,
              text: 'Get Started',
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
