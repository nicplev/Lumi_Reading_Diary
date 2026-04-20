import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../core/exceptions/linking_exceptions.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/user_school_index_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/lumi_text_styles.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../data/models/student_link_code_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/analytics_service.dart';
import '../../../services/crash_reporting_service.dart';
import '../../../services/parent_linking_service.dart';
import '../link_code_scanner_screen.dart';

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

const double _kMaxBlur = 18;
const double _kMaxDim = 0.18;

enum _Stage { code, name, email, password, confirm, success }

class _ParentRegistrationOverlay extends StatelessWidget {
  const _ParentRegistrationOverlay();

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
                  // easeInCubic — stays near 0 early so the blur visibly
                  // ramps up instead of hitting peak sigma immediately.
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
              // Keep the wrapper tree shape constant across the whole lifecycle
              // (swapping between `child` and `Opacity>Transform>child` re-parents
              // the card and causes a one-frame flicker on dismiss). Entrance
              // runs at opacity 1 / dy 0, so the card's own .animate() chain
              // drives the intro; during reverse we slide it off the bottom.
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
              child: const _ParentRegistrationCard(),
            ),
          ),
        ],
      ),
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

  StudentLinkCodeModel? _verifiedCode;
  Map<String, dynamic>? _studentInfo;
  UserModel? _createdParent;

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
    // Progressive reveal: tapping into the peek field commits the stage
    // advance so the previous field compacts to a chip.
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
    final code = _verifiedCode;
    if (code == null) return;

    setState(() {
      _busy = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final fullName =
        '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}';

    try {
      final indexService = UserSchoolIndexService();
      String userId;
      var isNewAccount = false;

      try {
        final cred = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        userId = cred.user!.uid;
        isNewAccount = true;
        await cred.user!.sendEmailVerification();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          try {
            final cred = await _auth.signInWithEmailAndPassword(
              email: email,
              password: password,
            );
            userId = cred.user!.uid;
            final existing = await _firestore
                .collection('schools')
                .doc(code.schoolId)
                .collection('parents')
                .doc(userId)
                .get();
            if (existing.exists &&
                code.status == LinkCodeStatus.used &&
                code.usedBy == userId) {
              if (!mounted) return;
              setState(() => _errorMessage =
                  'You are already registered and linked to this student. Please use the login page.');
              await _auth.signOut();
              return;
            }
          } on FirebaseAuthException catch (signInError) {
            if (signInError.code == 'wrong-password' ||
                signInError.code == 'invalid-credential') {
              if (!mounted) return;
              setState(() => _errorMessage =
                  'This email is already registered with a different password. If this is your account, please log in instead.');
              return;
            }
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      final parentRef = _firestore
          .collection('schools')
          .doc(code.schoolId)
          .collection('parents')
          .doc(userId);
      final existingDoc = await parentRef.get();

      if (!existingDoc.exists) {
        final parentUser = UserModel(
          id: userId,
          email: email,
          fullName: fullName,
          role: UserRole.parent,
          schoolId: code.schoolId,
          linkedChildren: const [],
          createdAt: DateTime.now(),
          isActive: true,
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
        await indexService.createOrUpdateIndex(
          email: email,
          schoolId: code.schoolId,
          userType: 'parent',
          userId: userId,
        );
      } else if (isNewAccount) {
        await parentRef.update({
          'fullName': fullName,
          'email': email,
          'linkedChildren': FieldValue.arrayUnion([code.studentId]),
        });
        await indexService.createOrUpdateIndex(
          email: email,
          schoolId: code.schoolId,
          userType: 'parent',
          userId: userId,
        );
      }

      try {
        await _linkingService.linkParentToStudent(
          code: code.code,
          parentUserId: userId,
          parentEmail: email,
        );
      } on AlreadyLinkedException {
        // Treat as success — already linked.
      }

      final refreshed = await parentRef.get();
      if (!mounted) return;
      setState(() {
        _createdParent = refreshed.exists ? UserModel.fromFirestore(refreshed) : null;
        _stage = _Stage.success;
      });
      AnalyticsService.instance.logParentLinkingCompleted();
    } on LinkingException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.userMessage);
      AnalyticsService.instance
          .logParentLinkingFailed(reason: e.runtimeType.toString());
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = _authErrorMessage(e.code));
      AnalyticsService.instance.logParentLinkingFailed(reason: e.code);
      await _auth.signOut();
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
    final parent = _createdParent;
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    navigator.pop();
    if (parent != null) {
      final route = AppRouter.getHomeRouteForRole(parent.role);
      router.go(route, extra: parent);
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
                    studentName: _studentName,
                    onStart: _finishAndGoHome,
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
      _Stage.code => 'Link your child',
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
        key: const ValueKey('chip_connected'),
        label: 'Connected to $_studentName',
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
          'Enter the 8-character code from your child\'s school.',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 12),
        LumiInput(
          controller: _codeController,
          hintText: 'e.g. ABC12345',
          autofocus: true,
          maxLength: 8,
          textInputAction: TextInputAction.done,
          prefixIcon: IconButton(
            onPressed: _busy ? null : _openQrScanner,
            tooltip: 'Scan QR code',
            icon: const Icon(Icons.qr_code_scanner, size: 22),
            color: AppColors.charcoal,
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
              'Your account is linked to $studentName. Let\'s start reading together.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            LumiPrimaryButton(
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
