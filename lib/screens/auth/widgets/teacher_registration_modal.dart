import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/services/user_school_index_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../data/models/user_model.dart';
import '../../../services/crash_reporting_service.dart';
import '../../../services/school_code_service.dart';

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

enum _Stage { code, name, email, password, confirm, success }

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
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _codeController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Stage _stage = _Stage.code;
  bool _busy = false;
  String? _errorMessage;

  String? _verifiedSchoolId;
  String? _verifiedSchoolName;
  String? _verifiedCodeId;
  UserModel? _createdTeacher;

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
    ]) {
      c.addListener(() => setState(() {}));
    }
    _firstNameController.addListener(_updateLastNameVisibility);
    _lastNameController.addListener(_updateLastNameVisibility);
    // Progressive reveal: when the user taps into the revealed "peek" field,
    // commit the stage advance so the previous field compacts to a chip.
    _passwordFocusNode.addListener(() {
      if (_passwordFocusNode.hasFocus && _stage == _Stage.email && _emailValid) {
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
    _lastNameRevealTimer?.cancel();
    _passwordFocusNode.dispose();
    _confirmFocusNode.dispose();
    _codeController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
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
        _stage = _Stage.name;
      });
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
  }

  void _goBack() {
final prev = switch (_stage) {
      _Stage.code => _Stage.code,
      _Stage.name => _Stage.code,
      _Stage.email => _Stage.name,
      _Stage.password => _Stage.email,
      _Stage.confirm => _Stage.password,
      _Stage.success => _Stage.success,
    };
    setState(() {
      _errorMessage = null;
      _stage = prev;
    });
  }

  Future<void> _createAccount() async {
    if (!_confirmValid) return;
    final schoolId = _verifiedSchoolId;
    final codeId = _verifiedCodeId;
    if (schoolId == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
            .trim();

    try {
      final indexService = UserSchoolIndexService();

      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final userId = cred.user!.uid;
      await cred.user!.updateDisplayName(fullName);
      await cred.user!.sendEmailVerification();

      final teacherUser = UserModel(
        id: userId,
        email: email,
        fullName: fullName,
        role: UserRole.teacher,
        schoolId: schoolId,
        createdAt: DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      await _firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(userId)
          .set({
        ...teacherUser.toFirestore(),
        'permissions': {
          'notifications': {
            'assignedClasses': true,
            'assignedStudents': true,
            'schedule': true,
            'wholeSchool': false,
          },
        },
      });

      try {
        await _firestore
            .collection('schools')
            .doc(schoolId)
            .update({'teacherCount': FieldValue.increment(1)});
      } catch (_) {
        // Non-critical; continue.
      }

      await indexService.createOrUpdateIndex(
        email: email,
        schoolId: schoolId,
        userType: 'user',
        userId: userId,
      );

      if (codeId != null) {
        try {
          await _schoolCodeService.incrementCodeUsage(codeId);
        } catch (_) {
          // Non-critical; the account is created.
        }
      }

      if (!mounted) return;
      setState(() {
        _createdTeacher = teacherUser;
        _stage = _Stage.success;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _authErrorMessage(e.code));
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
      try {
        await _auth.signOut();
      } catch (_) {}
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
                    schoolName: _verifiedSchoolName ?? 'your school',
                    onDone: _finishAndGoHome,
                  )
                : KeyedSubtree(
                    key: const ValueKey('form'),
                    child: _buildFormCard(),
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
      _Stage.code => 'Join your school',
      _Stage.name => 'Your name',
      _Stage.email => 'Email address',
      _Stage.password => 'Create password',
      _Stage.confirm => 'Confirm password',
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
                  color: AppColors.charcoal,
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
            color: AppColors.charcoal,
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
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          controller: _codeController,
          hintText: 'e.g. LUMI2024',
          autofocus: true,
          textInputAction: TextInputAction.done,
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
                    controller: _lastNameController,
                    hintText: 'Last name',
                    textInputAction: TextInputAction.done,
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
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
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
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          autofocus: true,
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
                    controller: _confirmController,
                    focusNode: _confirmFocusNode,
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
      controller: _confirmController,
      focusNode: _confirmFocusNode,
      autofocus: true,
      hintText: 'Re-enter password',
      errorText: _confirmController.text.isNotEmpty && !_confirmValid
          ? 'Passwords don\'t match'
          : null,
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
          'Create Account',
          _confirmValid && !_busy,
          _createAccount,
        ),
      _Stage.success => ('', false, () {}),
    };

    return LumiPrimaryButton(
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
        color: AppColors.mintGreen.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: LumiTextStyles.bodySmall(color: AppColors.success)
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
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.error.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: LumiTextStyles.bodySmall(color: AppColors.error),
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
                  color: AppColors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 42,
                  color: AppColors.success,
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
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            LumiPrimaryButton(
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
