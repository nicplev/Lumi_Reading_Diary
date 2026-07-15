import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_access.dart';
import '../../core/services/dev_access_service.dart';
import '../../core/services/functions_instance.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_input.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/phone_verification_recovery_service.dart';
import '../../services/sms_verification_service.dart';
import '../../core/services/user_school_index_service.dart';
import 'widgets/dev_access_modal.dart';
import 'widgets/parent_registration_modal.dart';
import 'widgets/teacher_registration_modal.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _SignInMode { email, phone }

enum _PhoneStage { enterNumber, enterCode }

enum _LoginLandingPage { welcome, signIn, join }

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final DevAccessService _devAccess = DevAccessService.instance;
  final SmsVerificationService _smsService = SmsVerificationService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  _LoginLandingPage _landingPage = _LoginLandingPage.welcome;

  // Phone sign-in sub-flow state. When `_signInMode` is `phone`, the email
  // form is hidden and a small phone-number + SMS-code panel takes its place.
  _SignInMode _signInMode = _SignInMode.email;
  _PhoneStage _phoneStage = _PhoneStage.enterNumber;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _phoneSmsController = TextEditingController();
  String? _phoneVerificationId;
  int? _phoneResendToken;

  static final RegExp _auMobileRegex = RegExp(r'^04\d{8}$');
  String get _phoneDigits =>
      _phoneController.text.replaceAll(RegExp(r'\s+'), '');
  bool get _phoneValid => _auMobileRegex.hasMatch(_phoneDigits);
  String get _phoneE164 => '+61${_phoneDigits.substring(1)}';
  bool get _smsCodeValid =>
      RegExp(r'^\d{6}$').hasMatch(_phoneSmsController.text.trim());

  @override
  void initState() {
    super.initState();
    // Rebuild whenever dev-access flips (e.g. the server lookup completes
    // after a session-resume, or after the long-press auth modal unlocks it).
    _devAccess.addListener(_onDevAccessChanged);
  }

  @override
  void dispose() {
    _devAccess.removeListener(_onDevAccessChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _phoneSmsController.dispose();
    super.dispose();
  }

  Future<void> _sendPhoneLoginCode() async {
    if (!_phoneValid) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: _phoneE164,
        forceResendingToken: _phoneResendToken,
        // Persist + warm-resume safety net. iOS pops modals more often
        // than full screens, so this is less likely to fire on the login
        // surface — but we keep the parity for force-quit / OS-interrupt
        // cases (incoming call, app switch mid-reCAPTCHA, etc.).
        onCodeSentPersist: (h) {
          final record = PendingPhoneVerification(
            verificationId: h.verificationId,
            resendToken: h.resendToken,
            phoneE164: _phoneE164,
            mode: PhoneVerificationMode.phoneLogin,
            contextJson: const {},
            savedAt: DateTime.now(),
          );
          unawaited(PhoneVerificationRecoveryService.instance.save(record));
          if (!mounted) {
            PhoneVerificationRecoveryService.instance.onRecoveryNeeded?.call(
              record,
            );
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _phoneVerificationId = handle.verificationId;
        _phoneResendToken = handle.resendToken;
        _phoneStage = _PhoneStage.enterCode;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Could not send code. Please check your number.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyPhoneLogin() async {
    final verificationId = _phoneVerificationId;
    if (verificationId == null || !_smsCodeValid) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cred = await _smsService.signInWithPhoneCode(
        verificationId: verificationId,
        smsCode: _phoneSmsController.text.trim(),
      );
      final uid = cred.user?.uid;
      if (uid == null) {
        throw FirebaseAuthException(
          code: 'no-user',
          message: 'Sign-in did not return a user.',
        );
      }

      final indexService = UserSchoolIndexService();
      final indexResult = await indexService.lookupSchoolByPhone(_phoneE164);
      if (indexResult == null) {
        await _discardPhoneSignIn(cred);
        if (!mounted) return;
        setState(
          () => _errorMessage =
              'We couldn\'t find an account for that phone number. If you\'re new, register below — parents join with a student code, teachers with a school code.',
        );
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
        await _discardPhoneSignIn(cred);
        if (!mounted) return;
        setState(
          () => _errorMessage =
              'Your profile is missing. Please contact your school administrator.',
        );
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

      if (!mounted) return;
      _navigateToHome(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Phone OTP sign-in implicitly CREATES an Auth user when the number is
  /// unknown. When this attempt minted a brand-new user that turns out to
  /// have no Lumi profile, delete it again so failed logins don't strand
  /// ghost phone-only accounts, then sign out.
  Future<void> _discardPhoneSignIn(UserCredential cred) async {
    if (cred.additionalUserInfo?.isNewUser == true) {
      try {
        await cred.user?.delete();
      } catch (_) {
        // Best-effort — the sign-out below still ends the session.
      }
    }
    await _firebaseService.signOut();
  }

  void _toggleSignInMode() {
    setState(() {
      _errorMessage = null;
      if (_signInMode == _SignInMode.email) {
        _signInMode = _SignInMode.phone;
        _phoneStage = _PhoneStage.enterNumber;
        _phoneSmsController.clear();
        _phoneVerificationId = null;
      } else {
        _signInMode = _SignInMode.email;
      }
    });
  }

  void _onDevAccessChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _showLandingPage(_LoginLandingPage page) {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      _landingPage = page;
    });
  }

  Future<void> _handleDevAccessGesture() async {
    // If the current user already has dev access, the section is already
    // visible — no modal needed.
    if (_devAccess.hasAccess) return;
    HapticFeedback.mediumImpact();
    await showDevAccessModal(context);
    // The DevAccessService listener will rebuild us if access was granted.
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      try {
        final indexService = UserSchoolIndexService();
        // Sign in with email and password. If the account has phone MFA
        // enrolled (teacher/parent signups flow it on) Firebase throws
        // FirebaseAuthMultiFactorException and we route through the SMS
        // challenge dialog before carrying on with the rest of the login.
        UserCredential? userCredential;
        try {
          userCredential = await _firebaseService.auth
              .signInWithEmailAndPassword(email: email, password: password);
        } on FirebaseAuthMultiFactorException catch (mfaError) {
          userCredential = await _resolveMfaChallenge(mfaError.resolver);
          if (userCredential == null) {
            // User cancelled or failed the challenge; _resolveMfaChallenge
            // has already set an error message (or none, if they hit cancel).
            if (mounted) setState(() => _isLoading = false);
            return;
          }
        }

        if (userCredential.user != null) {
          // Check email verification (allow unverified for now with a warning)
          if (!userCredential.user!.emailVerified) {
            // Resend verification email
            await _firebaseService.sendEmailVerification();
            if (!mounted) return;
            showLumiToast(
              message:
                  'Please verify your email address. A verification email has been sent.',
              type: LumiToastType.info,
              duration: const Duration(seconds: 5),
            );
          }

          // OPTIMIZED: Use email-to-school index for O(1) lookup
          UserModel? user;
          String? userSchoolId;

          // Try fast lookup using index first
          final indexResult = await indexService.lookupSchoolByEmail(email);

          if (indexResult != null) {
            // Found in index - direct lookup (2-3 reads total)
            final schoolId = indexResult['schoolId'] as String;
            final userType = indexResult['userType'] as String;
            final collectionName = userType == 'parent' ? 'parents' : 'users';

            final userDoc = await _firebaseService.firestore
                .collection('schools')
                .doc(schoolId)
                .collection(collectionName)
                .doc(userCredential.user!.uid)
                .get();

            if (userDoc.exists) {
              user = UserModel.fromFirestore(userDoc);
              userSchoolId = schoolId;
            }
          } else {
            // Fallback: not in the email index yet. Resolve the school
            // SERVER-SIDE via a Cloud callable instead of listing the whole
            // /schools collection client-side — that client `list` required an
            // over-broad rule that exposed every school's contact/subscription
            // data cross-tenant (security finding #5). The callable finds this
            // uid's own membership and backfills the index for next time.
            try {
              final resolve = await lumiFunctions
                  .httpsCallable('resolveUserSchoolByUid')
                  .call<Map<String, dynamic>>();
              final data =
                  Map<String, dynamic>.from(resolve.data as Map? ?? const {});
              final schoolId = data['schoolId'] as String?;
              final userType = (data['userType'] as String?) ?? 'user';

              if (schoolId != null && schoolId.isNotEmpty) {
                final collectionName =
                    userType == 'parent' ? 'parents' : 'users';
                final memberDoc = await _firebaseService.firestore
                    .collection('schools')
                    .doc(schoolId)
                    .collection(collectionName)
                    .doc(userCredential.user!.uid)
                    .get();
                if (memberDoc.exists) {
                  user = UserModel.fromFirestore(memberDoc);
                  userSchoolId = schoolId;
                }
              }
            } on FirebaseFunctionsException catch (_) {
              // not-found / unauthenticated → leave user null and fall through
              // to the last-resort top-level users check below.
            }
          }

          // Last resort: check top-level users collection (legacy setup scripts)
          if (user == null) {
            final topLevelDoc = await _firebaseService.firestore
                .collection('users')
                .doc(userCredential.user!.uid)
                .get();

            if (topLevelDoc.exists) {
              user = UserModel.fromFirestore(topLevelDoc);
              userSchoolId = user.schoolId;

              // Migrate: copy to school subcollection for future logins
              if (userSchoolId != null && userSchoolId.isNotEmpty) {
                await _firebaseService.firestore
                    .collection('schools')
                    .doc(userSchoolId)
                    .collection('users')
                    .doc(userCredential.user!.uid)
                    .set(topLevelDoc.data()!);

                // Create index entry
                await indexService.createOrUpdateIndex(
                  email: email,
                  schoolId: userSchoolId,
                  userType: 'user',
                  userId: userCredential.user!.uid,
                );
              }
            }
          }

          if (user != null && userSchoolId != null) {
            // Update last login time
            final isParent = user.role == UserRole.parent;
            await _firebaseService.firestore
                .collection('schools')
                .doc(userSchoolId)
                .collection(isParent ? 'parents' : 'users')
                .doc(userCredential.user!.uid)
                .update({'lastLoginAt': FieldValue.serverTimestamp()});

            // Register the FCM token via the single auth entry point. No-op
            // for non-parents or users without a school.
            NotificationService.instance.onParentAuthenticated(user);

            if (!mounted) return;

            // Navigate based on role
            _navigateToHome(user);
          } else {
            throw Exception('User profile not found');
          }
        }
      } on FirebaseAuthException catch (e) {
        setState(() {
          _errorMessage = _getErrorMessage(e.code);
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'An error occurred. Please try again.';
        });
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please wait a few minutes before trying again.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  /// Sends the SMS challenge for a MFA-required login and prompts the user
  /// for the 6-digit code. Returns the completed [UserCredential] on success,
  /// or null if the user cancelled or the challenge failed (in which case
  /// [_errorMessage] is set).
  Future<UserCredential?> _resolveMfaChallenge(
    MultiFactorResolver resolver,
  ) async {
    SmsCodeHandle handle;
    try {
      handle = await _smsService.sendLoginCode(resolver: resolver);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
      return null;
    } catch (e) {
      setState(
        () => _errorMessage =
            'Could not send verification code. Please try again.',
      );
      return null;
    }

    if (!mounted) return null;

    final hint = resolver.hints.first;
    final phoneHint = hint is PhoneMultiFactorInfo ? hint.phoneNumber : null;

    final smsCode = await _promptForSmsCode(
      phoneHint: phoneHint,
      onResend: () async {
        try {
          final resent = await _smsService.sendLoginCode(
            resolver: resolver,
            forceResendingToken: handle.resendToken,
          );
          handle = resent;
        } on FirebaseAuthException catch (e) {
          if (mounted) {
            showLumiToast(
              message: SmsVerificationService.friendlyError(e),
              type: LumiToastType.error,
            );
          }
          rethrow;
        }
      },
    );

    if (smsCode == null) {
      // User cancelled. Leave _errorMessage null so we don't shout at them.
      return null;
    }

    try {
      return await _smsService.resolveLogin(
        resolver: resolver,
        verificationId: handle.verificationId,
        smsCode: smsCode,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
      return null;
    } catch (_) {
      setState(
        () => _errorMessage = 'Could not verify the code. Please try again.',
      );
      return null;
    }
  }

  Future<String?> _promptForSmsCode({
    required String? phoneHint,
    required Future<void> Function() onResend,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _MfaCodeDialog(phoneHint: phoneHint, onResend: onResend),
    );
  }

  void _navigateToHome(UserModel user) {
    // Check if parent is trying to access web version
    final redirectRoute = AppRouter.checkParentWebAccess(user.role);
    if (redirectRoute != null) {
      context.go(redirectRoute);
      return;
    }

    // Navigate to role-based home screen. Don't pass UserModel via `extra`
    // (no codec → iOS state restoration crashes); the route reads from
    // userProvider instead.
    final homeRoute = AppRouter.getHomeRouteForRole(user.role);
    final firstParentLogin =
        user.role == UserRole.parent && user.lastLoginAt == null;
    context.go(
      firstParentLogin
          ? Uri(
              path: homeRoute,
              queryParameters: const {'firstParentLogin': '1'},
            ).toString()
          : homeRoute,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_landingPage) {
      case _LoginLandingPage.welcome:
        return _buildWelcomeScreen(context);
      case _LoginLandingPage.join:
        return _buildJoinScreen(context);
      case _LoginLandingPage.signIn:
        return _buildSignInScreen(context);
    }
  }

  Widget _buildWelcomeScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The character deliberately extends past the bottom edge. This
            // standalone high-resolution asset stays crisp at the large,
            // peeking-up size used here.
            final mascotWidth = constraints.maxWidth;
            final mascotHeight = mascotWidth * (623 / 457);
            // Keep Lumi's mouth above the device home indicator while the
            // character still peeks from the bottom edge.
            final mascotBottom = constraints.maxHeight < 700 ? -225.0 : -210.0;
            // Reserve a little more visual space below actions on taller
            // screens, lifting the copy/buttons away from Lumi's flame.
            final bottomActionSpace = constraints.maxHeight < 700
                ? mascotHeight * 0.50
                : mascotHeight * 0.56;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // A restrained floating cluster keeps the upper half lively,
                // while leaving the wordmark and welcome message in charge.
                const Positioned(
                  top: 26,
                  left: -20,
                  child: _FloatingAuthCircle(
                    size: 54,
                    color: LumiTokens.tintRed,
                    drift: Offset(6, 7),
                    duration: Duration(milliseconds: 9200),
                  ),
                ),
                const Positioned(
                  top: 52,
                  right: 34,
                  child: _FloatingAuthCircle(
                    size: 22,
                    color: LumiTokens.yellow,
                    drift: Offset(-4, 6),
                    duration: Duration(milliseconds: 7800),
                  ),
                ),
                const Positioned(
                  top: 108,
                  right: -22,
                  child: _FloatingAuthCircle(
                    size: 50,
                    color: LumiTokens.tintBlue,
                    drift: Offset(-6, 5),
                    duration: Duration(milliseconds: 9700),
                  ),
                ),
                const Positioned(
                  top: 148,
                  left: 34,
                  child: _FloatingAuthCircle(
                    size: 18,
                    color: LumiTokens.green,
                    drift: Offset(5, -5),
                    duration: Duration(milliseconds: 6800),
                  ),
                ),
                const Positioned(
                  top: 208,
                  left: 104,
                  child: _FloatingAuthCircle(
                    size: 16,
                    color: LumiTokens.tintYellow,
                    drift: Offset(-4, 5),
                    duration: Duration(milliseconds: 8300),
                  ),
                ),
                const Positioned(
                  top: 226,
                  right: 48,
                  child: _FloatingAuthCircle(
                    size: 22,
                    color: LumiTokens.blue,
                    drift: Offset(4, 6),
                    duration: Duration(milliseconds: 8600),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: mascotBottom,
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: <Type, GestureRecognizerFactory>{
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                              LongPressGestureRecognizer>(
                        () => LongPressGestureRecognizer(
                          duration: const Duration(seconds: 5),
                        ),
                        (LongPressGestureRecognizer instance) {
                          instance.onLongPress = _handleDevAccessGesture;
                        },
                      ),
                    },
                    child: IgnorePointer(
                      child: ExcludeSemantics(
                        child: Image.asset(
                          'assets/UI Lumi/Red_Lumi_Default_EyesUp.png',
                          width: mascotWidth,
                          height: mascotHeight,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Text(
                          'Lumi',
                          style: LumiType.button.copyWith(
                            color: LumiTokens.charcoal,
                          ),
                        ),
                      ).animate().fadeIn(duration: 350.ms),
                      const Spacer(flex: 3),
                      Text(
                        'Home reading,\nmade simple.',
                        style: LumiType.displayL.copyWith(
                          color: LumiTokens.charcoal,
                          height: 1.08,
                        ),
                      ).animate().fadeIn(delay: 100.ms, duration: 450.ms),
                      const SizedBox(height: 14),
                      Text(
                        'Log reading in seconds.\nKeep families and teachers connected.',
                        style: LumiType.body.copyWith(
                          color: LumiTokens.ink.withValues(alpha: 0.68),
                          height: 1.45,
                        ),
                      ).animate().fadeIn(delay: 190.ms, duration: 450.ms),
                      const SizedBox(height: 28),
                      LumiPrimaryButton(
                        onPressed: () =>
                            _showLandingPage(_LoginLandingPage.join),
                        text: 'Create account',
                        isFullWidth: true,
                        color: LumiTokens.red,
                        borderRadius: BorderRadius.circular(
                          LumiTokens.radiusPill,
                        ),
                      ).animate().fadeIn(delay: 280.ms, duration: 400.ms),
                      const SizedBox(height: 18),
                      LumiSecondaryButton(
                        onPressed: () =>
                            _showLandingPage(_LoginLandingPage.signIn),
                        text: 'I already have an account',
                        isFullWidth: true,
                        color: LumiTokens.red,
                        borderRadius: BorderRadius.circular(
                          LumiTokens.radiusPill,
                        ),
                      ).animate().fadeIn(delay: 340.ms, duration: 400.ms),
                      // Keep both actions clear of Lumi's head while still
                      // allowing the mascot to peek out from the bottom.
                      SizedBox(height: bottomActionSpace),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildJoinScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactHeight = constraints.maxHeight < 720;
            final isNarrow = constraints.maxWidth < 360;
            final horizontalPadding = isNarrow ? 18.0 : 24.0;
            final bottomPadding = isCompactHeight ? 20.0 : 28.0;
            final artworkHeight = isCompactHeight ? 96.0 : 116.0;
            final headingSize = isCompactHeight ? 28.0 : 32.0;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  bottomPadding,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 520,
                      minHeight: constraints.maxHeight - 12 - bottomPadding,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              onPressed: () => _showLandingPage(
                                _LoginLandingPage.welcome,
                              ),
                              icon: const Icon(Icons.arrow_back_rounded),
                              color: LumiTokens.ink,
                              tooltip: 'Back',
                            ),
                          ),
                          SizedBox(height: isCompactHeight ? 2 : 8),
                          Center(
                            child: Image.asset(
                              'assets/UI Lumi/Lumi signup.png',
                              height: artworkHeight,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              semanticLabel: 'Lumi ready to help you sign up',
                            ),
                          )
                              .animate()
                              .fadeIn(duration: 350.ms)
                              .scale(begin: const Offset(.94, .94)),
                          SizedBox(height: isCompactHeight ? 14 : 18),
                          Text(
                            'How will you use Lumi?',
                            style: LumiType.displayL.copyWith(
                              fontSize: headingSize,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(
                                delay: 100.ms,
                                duration: 400.ms,
                              ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose the option that best describes you.',
                            style: LumiType.body.copyWith(
                              color: LumiTokens.muted,
                              fontSize: isCompactHeight ? 15 : 16,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(
                                delay: 160.ms,
                                duration: 400.ms,
                              ),
                          SizedBox(height: isCompactHeight ? 22 : 28),
                          _RoleTile(
                            icon: Icons.family_restroom,
                            accent: LumiTokens.red,
                            title: 'Parent or Guardian',
                            subtitle: 'Connect with your child and log reading',
                            onTap: () => showParentRegistrationModal(context),
                          ),
                          const SizedBox(height: 12),
                          _RoleTile(
                            icon: Icons.school_rounded,
                            accent: LumiTokens.green,
                            title: 'Teacher',
                            subtitle: 'Set up your class and track reading',
                            onTap: () => showTeacherRegistrationModal(context),
                          ),
                          const Spacer(),
                          SizedBox(height: isCompactHeight ? 22 : 28),
                          Center(
                            child: TextButton(
                              onPressed: () => _showLandingPage(
                                _LoginLandingPage.signIn,
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: LumiTokens.ink,
                                minimumSize: const Size(44, 44),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LumiTokens.space3,
                                  vertical: LumiTokens.space2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusPill,
                                  ),
                                ),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: LumiType.button.copyWith(
                                    color: LumiTokens.muted,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: 'Already have an account? ',
                                    ),
                                    TextSpan(
                                      text: 'Log in',
                                      style: TextStyle(
                                        color: LumiTokens.red,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSignInScreen(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardInset = mediaQuery.viewInsets.bottom;
    final screenSize = mediaQuery.size;
    final safeHeight = screenSize.height - mediaQuery.padding.vertical;
    final isCompactHeight = safeHeight < 720;
    final isSpaciousHeight = safeHeight > 940;
    final isNarrow = screenSize.width < 360;
    final horizontalPadding = isNarrow ? 18.0 : 24.0;
    final bottomPadding = isCompactHeight ? 24.0 : 36.0;
    // Always reserve a clear navigation lane above the face. On short phones
    // the page scrolls, but the back action must never overlap Lumi's eye.
    final topContentSpacing =
        isCompactHeight ? 52.0 : (isSpaciousHeight ? 72.0 : 64.0);
    final eyesWidth =
        (screenSize.width - (horizontalPadding * 2) - (isNarrow ? 32 : 56))
            .clamp(230.0, 380.0)
            .toDouble();
    final eyesToTitleSpacing = isCompactHeight ? 16.0 : 24.0;
    final headingSize = isCompactHeight ? 30.0 : 32.0;
    final titleToFormSpacing = isCompactHeight ? 14.0 : 18.0;
    final fieldSpacing = isCompactHeight ? 4.0 : 8.0;
    final primaryButtonSpacing = isCompactHeight ? 8.0 : 12.0;
    final alternativeSpacing = isCompactHeight ? 14.0 : 20.0;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: LumiTokens.red,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: LumiTokens.red,
        body: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                0,
                horizontalPadding,
                bottomPadding + keyboardInset,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Taller phones get a little top breathing room to keep
                          // the form visually centred. Compact/keyboard layouts
                          // stay tight and remain fully scrollable.
                          SizedBox(height: topContentSpacing),
                          Center(
                            child: Animate(
                              effects: const [
                                FadeEffect(
                                    duration: Duration(milliseconds: 500)),
                              ],
                              child: RawGestureDetector(
                                behavior: HitTestBehavior.opaque,
                                gestures: <Type, GestureRecognizerFactory>{
                                  LongPressGestureRecognizer:
                                      GestureRecognizerFactoryWithHandlers<
                                          LongPressGestureRecognizer>(
                                    () => LongPressGestureRecognizer(
                                      duration: const Duration(seconds: 5),
                                    ),
                                    (LongPressGestureRecognizer instance) {
                                      instance.onLongPress =
                                          _handleDevAccessGesture;
                                    },
                                  ),
                                },
                                child: Image.asset(
                                  'assets/UI Lumi/Lumi_Eyes.png',
                                  width: eyesWidth,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  semanticLabel: 'Lumi face',
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: eyesToTitleSpacing),

                          Text(
                            'Welcome back',
                            style: LumiType.displayL.copyWith(
                              color: LumiTokens.paper,
                              fontSize: headingSize,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(delay: 150.ms, duration: 500.ms),

                          const SizedBox(height: 6),

                          Text(
                            'Sign in to your Lumi account.',
                            style: LumiType.body.copyWith(
                              color: LumiTokens.paper.withValues(alpha: 0.76),
                              fontSize: isCompactHeight ? 15 : 16,
                            ),
                            textAlign: TextAlign.center,
                          ).animate().fadeIn(delay: 250.ms, duration: 500.ms),

                          SizedBox(height: titleToFormSpacing),

                          // Error message
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: LumiTokens.paper.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusSmall,
                                ),
                                border: Border.all(
                                  color:
                                      LumiTokens.paper.withValues(alpha: 0.58),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: LumiTokens.paper,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: LumiType.caption.copyWith(
                                        color: LumiTokens.paper,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ).animate().fadeIn().shake(),
                            const SizedBox(height: 16),
                          ],

                          if (_signInMode == _SignInMode.email) ...[
                            // Email + password form. AutofillGroup ties the pair so the
                            // OS can fill saved credentials and offer to save on submit.
                            AutofillGroup(
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    _AuthTextField(
                                      controller: _emailController,
                                      label: 'Email address',
                                      hintText: 'name@example.com',
                                      onRed: true,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      autofillHints: const [
                                        AutofillHints.username,
                                        AutofillHints.email,
                                      ],
                                      validator: FormBuilderValidators.compose([
                                        FormBuilderValidators.required(
                                          errorText: 'Email is required',
                                        ),
                                        FormBuilderValidators.email(
                                          errorText: 'Enter a valid email',
                                        ),
                                      ]),
                                    ).animate().fadeIn(
                                        delay: 400.ms, duration: 500.ms),
                                    SizedBox(height: fieldSpacing),
                                    _AuthTextField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      hintText: 'Enter your password',
                                      isPassword: true,
                                      onRed: true,
                                      textInputAction: TextInputAction.done,
                                      autofillHints: const [
                                        AutofillHints.password
                                      ],
                                      onSubmitted: (_) =>
                                          _isLoading ? null : _handleLogin(),
                                      validator: FormBuilderValidators.required(
                                        errorText: 'Password is required',
                                      ),
                                    ).animate().fadeIn(
                                        delay: 500.ms, duration: 500.ms),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Forgot password — quiet, sits with the password field.
                            Align(
                              alignment: Alignment.centerRight,
                              child: LumiTextButton(
                                onPressed: () =>
                                    context.push('/auth/forgot-password'),
                                text: 'Forgot password?',
                                color: LumiTokens.paper,
                              )
                                  .animate()
                                  .fadeIn(delay: 600.ms, duration: 500.ms),
                            ),
                            SizedBox(height: primaryButtonSpacing),
                            LumiPrimaryButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              text: 'Log in',
                              isLoading: _isLoading,
                              color: LumiTokens.paper,
                              foregroundColor: LumiTokens.red,
                              elevation: 0,
                              borderRadius:
                                  BorderRadius.circular(LumiTokens.radiusPill),
                            ).animate().fadeIn(delay: 650.ms, duration: 500.ms),
                            SizedBox(height: alternativeSpacing),
                            const _AuthDivider(label: 'or', onRed: true),
                            SizedBox(height: primaryButtonSpacing),
                            _AuthAlternativeButton(
                              onPressed: _isLoading ? null : _toggleSignInMode,
                              text: 'Continue with phone',
                              onRed: true,
                            ),
                          ] else ...[
                            // Phone-primary sub-form
                            _AuthTextField(
                              controller: _phoneController,
                              label: 'Mobile number',
                              hintText: '0400 000 000',
                              onRed: true,
                              helperText:
                                  'Australian mobile, e.g. 0400 000 000',
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [
                                AutofillHints.telephoneNumber
                              ],
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[\d\s]')),
                              ],
                              enabled: _phoneStage == _PhoneStage.enterNumber &&
                                  !_isLoading,
                              onChanged: (_) => setState(() {}),
                            ),
                            if (_phoneStage == _PhoneStage.enterCode) ...[
                              const SizedBox(height: 8),
                              _AuthTextField(
                                controller: _phoneSmsController,
                                label: 'Verification code',
                                hintText: '6-digit code',
                                onRed: true,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                autofillHints: const [
                                  AutofillHints.oneTimeCode
                                ],
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(6),
                                ],
                                onChanged: (_) {
                                  setState(() {});
                                  if (_smsCodeValid && !_isLoading) {
                                    _verifyPhoneLogin();
                                  }
                                },
                              ),
                            ],
                            const SizedBox(height: 24),
                            LumiPrimaryButton(
                              onPressed: _isLoading
                                  ? null
                                  : (_phoneStage == _PhoneStage.enterNumber
                                      ? (_phoneValid
                                          ? _sendPhoneLoginCode
                                          : null)
                                      : (_smsCodeValid
                                          ? _verifyPhoneLogin
                                          : null)),
                              text: _phoneStage == _PhoneStage.enterNumber
                                  ? 'Send code'
                                  : 'Verify & sign in',
                              isLoading: _isLoading,
                              color: LumiTokens.paper,
                              foregroundColor: LumiTokens.red,
                              elevation: 0,
                              borderRadius:
                                  BorderRadius.circular(LumiTokens.radiusPill),
                            ),
                            SizedBox(height: alternativeSpacing),
                            const _AuthDivider(label: 'or', onRed: true),
                            SizedBox(height: primaryButtonSpacing),
                            _AuthAlternativeButton(
                              onPressed: _isLoading ? null : _toggleSignInMode,
                              text: 'Continue with email',
                              onRed: true,
                            ),
                          ],

                          SizedBox(height: alternativeSpacing),
                          Center(
                            child: TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : () =>
                                      _showLandingPage(_LoginLandingPage.join),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LumiTokens.space3,
                                  vertical: LumiTokens.space2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusSmall,
                                  ),
                                ),
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: LumiType.button.copyWith(
                                    fontSize: 16,
                                    color: LumiTokens.paper
                                        .withValues(alpha: 0.76),
                                  ),
                                  children: const [
                                    TextSpan(text: 'New to Lumi? '),
                                    TextSpan(
                                      text: 'Create an account',
                                      style: TextStyle(color: LumiTokens.paper),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ).animate().fadeIn(delay: 750.ms, duration: 500.ms),

                          // HIDDEN (2026-06): "Represent a school? Request a demo" entry
                          // point. The demo-request flow is moving to the marketing
                          // landing-page website. Code is preserved so it can be
                          // re-enabled later — see the /onboarding/demo route and
                          // SchoolDemoScreen / DemoRequestScreen.
                          // const SizedBox(height: 12),
                          //
                          // School demo is a rarer, sales-style path — keep it a quiet
                          // text link so it doesn't compete with the two primary tiles.
                          // Center(
                          //   child: LumiTextButton(
                          //     onPressed: () => context.push('/onboarding/demo'),
                          //     text: 'Represent a school? Request a demo',
                          //     color: LumiTokens.muted,
                          //   ),
                          // ).animate().fadeIn(delay: 900.ms, duration: 500.ms),
                          if (hasDevAccess()) ...[
                            const SizedBox(height: 32),
                            // DEV ONLY: Create admin account button
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusSmall,
                                ),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'DEV ONLY',
                                    style: LumiType.caption.copyWith(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  LumiTextButton(
                                    onPressed: () {
                                      if (_firebaseService.auth.currentUser ==
                                          null) {
                                        showLumiToast(
                                          message:
                                              'Sign in to your dev account first.',
                                          type: LumiToastType.info,
                                        );
                                        return;
                                      }
                                      context.push('/dev/impersonate');
                                    },
                                    text: 'Impersonate School (read-only)',
                                    icon: Icons.shield_outlined,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        child: IconButton(
                          onPressed: () =>
                              _showLandingPage(_LoginLandingPage.welcome),
                          icon: const Icon(Icons.arrow_back_rounded),
                          color: LumiTokens.paper,
                          tooltip: 'Back to welcome',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _AuthCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _FloatingAuthCircle extends StatelessWidget {
  const _FloatingAuthCircle({
    required this.size,
    required this.color,
    required this.drift,
    required this.duration,
  });

  final double size;
  final Color color;
  final Offset drift;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final circle = ExcludeSemantics(
      child: _AuthCircle(size: size, color: color),
    );

    // Decorative movement must not create unnecessary motion for people who
    // have requested reduced motion at system level.
    if (MediaQuery.disableAnimationsOf(context)) return circle;

    return circle
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .move(
          begin: Offset.zero,
          end: drift,
          duration: duration,
          curve: Curves.easeInOutSine,
        )
        .scale(
          begin: const Offset(1, 1),
          end: const Offset(1.04, 1.04),
          duration: duration,
          curve: Curves.easeInOutSine,
        );
  }
}

/// A quiet divider between the password flow and phone alternative.
class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label, this.onRed = false});

  final String label;
  final bool onRed;

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        onRed ? LumiTokens.paper.withValues(alpha: 0.32) : LumiTokens.rule;
    final labelColor =
        onRed ? LumiTokens.paper.withValues(alpha: 0.76) : LumiTokens.muted;
    return Row(
      children: [
        Expanded(child: Divider(color: dividerColor, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LumiTokens.space3),
          child: Text(
            label,
            style: LumiType.caption.copyWith(color: labelColor),
          ),
        ),
        Expanded(child: Divider(color: dividerColor, height: 1)),
      ],
    );
  }
}

/// A compact alternative sign-in action. It remains comfortably tappable but
/// does not compete with the primary email-and-password path.
class _AuthAlternativeButton extends StatelessWidget {
  const _AuthAlternativeButton({
    required this.onPressed,
    required this.text,
    this.onRed = false,
  });

  final VoidCallback? onPressed;
  final String text;
  final bool onRed;

  @override
  Widget build(BuildContext context) {
    final enabledForeground =
        onRed ? LumiTokens.paper.withValues(alpha: 0.86) : LumiTokens.charcoal;
    final foreground = onPressed == null
        ? enabledForeground.withValues(alpha: 0.45)
        : enabledForeground;
    final borderColor = onRed ? Colors.transparent : LumiTokens.rule;
    return Center(
      child: SizedBox(
        width: 232,
        height: 44,
        child: Semantics(
          button: true,
          label: text,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
              // This action is intentionally presented as a text link. Keep
              // the accessible 44pt hit area without revealing its invisible
              // pill bounds through a Material ripple or pressed highlight.
              splashFactory: NoSplash.splashFactory,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                ),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: LumiType.button.copyWith(
                    color: foreground,
                    fontSize: 15,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Auth-only input surface for the current Lumi visual language. Resting
/// fields are deliberately borderless. Validation alone adds a red outline so
/// corrections are unambiguous without creating visual noise while typing.
class _AuthTextField extends StatefulWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.helperText,
    this.keyboardType,
    this.enabled = true,
    this.isPassword = false,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.inputFormatters,
    this.textInputAction,
    this.autofillHints,
    this.onRed = false,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String? helperText;
  final TextInputType? keyboardType;
  final bool enabled;
  final bool isPassword;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final List<String>? autofillHints;
  final bool onRed;

  @override
  State<_AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<_AuthTextField> {
  bool _obscureText = true;

  OutlineInputBorder _borderless() {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      borderSide: BorderSide.none,
    );
  }

  OutlineInputBorder _border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showPasswordToggle = widget.isPassword;
    final foregroundColor = widget.onRed ? LumiTokens.paper : LumiTokens.ink;
    final hintColor = widget.onRed
        ? LumiTokens.paper.withValues(alpha: 0.64)
        : LumiTokens.muted.withValues(alpha: 0.72);
    final errorColor = widget.onRed ? LumiTokens.paper : LumiTokens.red;
    final activeToggleBackground = widget.onRed
        ? LumiTokens.paper.withValues(alpha: 0.18)
        : LumiTokens.tintRed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: LumiType.caption.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        TextFormField(
          controller: widget.controller,
          keyboardType: widget.keyboardType,
          obscureText: showPasswordToggle && _obscureText,
          obscuringCharacter: '•',
          enabled: widget.enabled,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          validator: widget.validator,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          scrollPadding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + LumiTokens.space5,
          ),
          style: LumiType.body.copyWith(
            color: foregroundColor,
            fontWeight: FontWeight.w400,
          ),
          cursorColor: foregroundColor,
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: LumiType.body.copyWith(
              color: hintColor,
            ),
            filled: true,
            // Matching the page background keeps fields genuinely borderless.
            fillColor: widget.onRed ? LumiTokens.red : LumiTokens.cream,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            border: _borderless(),
            enabledBorder: _borderless(),
            focusedBorder: _borderless(),
            errorBorder: _border(errorColor, 1.25),
            focusedErrorBorder: _border(errorColor, 1.25),
            disabledBorder: _borderless(),
            errorMaxLines: 2,
            errorStyle: LumiType.caption.copyWith(
              color: errorColor,
              height: 1.3,
            ),
            suffixIcon: showPasswordToggle
                ? IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: _obscureText
                          ? Colors.transparent
                          : activeToggleBackground,
                      foregroundColor:
                          _obscureText ? hintColor : foregroundColor,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => setState(
                      () => _obscureText = !_obscureText,
                    ),
                    icon: Icon(
                      _obscureText
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _obscureText ? 'Show password' : 'Hide password',
                  )
                : null,
          ),
        ),
        if (widget.helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.helperText!,
            style: LumiType.caption.copyWith(color: hintColor),
          ),
        ],
      ],
    );
  }
}

/// Flat role-selection card with a subtle border, restrained pressed state,
/// and a chevron because tapping immediately opens the matching signup flow.
class _RoleTile extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RoleTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: LumiTokens.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: LumiTokens.rule),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: accent.withValues(alpha: 0.08),
        highlightColor: accent.withValues(alpha: 0.06),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: LumiType.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.muted,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: LumiTokens.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog that collects a 6-digit SMS code as a second factor. Pops with the
/// entered code on submit or null on cancel. [onResend] calls back into the
/// parent so Firebase can dispatch a fresh code with the correct resend token.
class _MfaCodeDialog extends StatefulWidget {
  final String? phoneHint;
  final Future<void> Function() onResend;

  const _MfaCodeDialog({required this.phoneHint, required this.onResend});

  @override
  State<_MfaCodeDialog> createState() => _MfaCodeDialogState();
}

class _MfaCodeDialogState extends State<_MfaCodeDialog> {
  final _codeController = TextEditingController();
  bool _resending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool get _codeValid =>
      RegExp(r'^\d{6}$').hasMatch(_codeController.text.trim());

  /// Recovery guidance for a parent who can no longer receive the SMS (e.g.
  /// their phone number changed). Self-service factor reset isn't possible
  /// without the old factor, so we point them at the school / support rather
  /// than leaving Resend/Cancel as the only options (a hard lockout).
  void _showCantReceiveHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Trouble with your code?', style: LumiType.subhead),
        content: Text(
          "Check that your phone has signal, then tap Resend.\n\n"
          "If your phone number has changed and you can no longer receive "
          "codes, your school can reset your account access — contact your "
          "school office, or email support@lumi-reading.com.",
          style: LumiType.body.copyWith(color: LumiTokens.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Got it',
              style: LumiType.button.copyWith(
                color: LumiTokens.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.phoneHint != null && widget.phoneHint!.isNotEmpty
        ? 'Enter the 6-digit code sent to ${widget.phoneHint}.'
        : 'Enter the 6-digit code we just sent to your phone.';
    return AlertDialog(
      backgroundColor: LumiTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      title: Text('Verify it\'s you', style: LumiType.subhead),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            subtitle,
            style: LumiType.body.copyWith(color: LumiTokens.muted),
          ),
          const SizedBox(height: 16),
          LumiInput(
            controller: _codeController,
            label: 'SMS code',
            keyboardType: TextInputType.number,
            autofocus: true,
            accentColor: LumiTokens.red,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resending
                  ? null
                  : () async {
                      setState(() => _resending = true);
                      try {
                        await widget.onResend();
                        if (!context.mounted) return;
                        _codeController.clear();
                        showLumiToast(
                          message: 'New code sent. Use the newest SMS code.',
                          type: LumiToastType.success,
                        );
                      } catch (_) {
                        // The parent callback already surfaced the error.
                      } finally {
                        if (mounted) setState(() => _resending = false);
                      }
                    },
              child: Text(
                _resending ? 'Sending…' : 'Resend code',
                style: LumiType.caption.copyWith(
                  color: _resending ? LumiTokens.muted : LumiTokens.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _showCantReceiveHelp(context),
              child: Text(
                "Can't receive the code?",
                style: LumiType.caption.copyWith(
                  color: LumiTokens.muted,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: LumiType.button.copyWith(color: LumiTokens.muted),
          ),
        ),
        TextButton(
          onPressed: _codeValid
              ? () => Navigator.of(context).pop(_codeController.text.trim())
              : null,
          child: Text(
            'Verify',
            style: LumiType.button.copyWith(
              color: _codeValid
                  ? LumiTokens.red
                  : LumiTokens.muted.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
