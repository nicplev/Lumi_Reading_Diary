import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_access.dart';
import '../../core/services/dev_access_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_input.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/phone_verification_recovery_service.dart';
import '../../services/sms_verification_service.dart';
import '../../core/services/user_school_index_service.dart';
import '../../utils/setup_test_data.dart';
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

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final DevAccessService _devAccess = DevAccessService.instance;
  final SmsVerificationService _smsService = SmsVerificationService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

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
    // Rebuild whenever dev-access flips (e.g. Firestore lookup completes
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
            PhoneVerificationRecoveryService.instance.onRecoveryNeeded
                ?.call(record);
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
      setState(() =>
          _errorMessage = 'Could not send code. Please check your number.');
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
        await _firebaseService.signOut();
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

      if (!mounted) return;
      _navigateToHome(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = SmsVerificationService.friendlyError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _errorMessage = 'Verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          userCredential =
              await _firebaseService.auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please verify your email address. A verification email has been sent.',
                ),
                duration: Duration(seconds: 5),
              ),
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
            // Fallback: Index not found (existing users before optimization)
            // Iterate through schools (legacy behavior for backward compatibility)
            final schoolsSnapshot =
                await _firebaseService.firestore.collection('schools').get();

            for (final schoolDoc in schoolsSnapshot.docs) {
              final schoolId = schoolDoc.id;

              // Try to find user in this school's users collection
              final userDoc = await _firebaseService.firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('users')
                  .doc(userCredential.user!.uid)
                  .get();

              if (userDoc.exists) {
                user = UserModel.fromFirestore(userDoc);
                userSchoolId = schoolId;

                // Backfill the index for this user for future logins
                await indexService.createOrUpdateIndex(
                  email: email,
                  schoolId: schoolId,
                  userType: 'user',
                  userId: userCredential.user!.uid,
                );
                break;
              }

              // Also check parents collection
              final parentDoc = await _firebaseService.firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('parents')
                  .doc(userCredential.user!.uid)
                  .get();

              if (parentDoc.exists) {
                user = UserModel.fromFirestore(parentDoc);
                userSchoolId = schoolId;

                // Backfill the index for this user for future logins
                await indexService.createOrUpdateIndex(
                  email: email,
                  schoolId: schoolId,
                  userType: 'parent',
                  userId: userCredential.user!.uid,
                );
                break;
              }
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
                .update({
              'lastLoginAt': FieldValue.serverTimestamp(),
            });

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
      MultiFactorResolver resolver) async {
    SmsCodeHandle handle;
    try {
      handle = await _smsService.sendLoginCode(resolver: resolver);
    } on FirebaseAuthException catch (e) {
      setState(() =>
          _errorMessage = SmsVerificationService.friendlyError(e));
      return null;
    } catch (e) {
      setState(() =>
          _errorMessage = 'Could not send verification code. Please try again.');
      return null;
    }

    if (!mounted) return null;

    final hint = resolver.hints.first;
    final phoneHint =
        hint is PhoneMultiFactorInfo ? hint.phoneNumber : null;

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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(SmsVerificationService.friendlyError(e)),
              ),
            );
          }
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
      setState(() =>
          _errorMessage = SmsVerificationService.friendlyError(e));
      return null;
    } catch (_) {
      setState(() =>
          _errorMessage = 'Could not verify the code. Please try again.');
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
    context.go(homeRoute);
  }

  void _showCreateAdminDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: const Text('Create Admin Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Use a real email you can verify.',
              style: LumiType.caption,
            ),
            const SizedBox(height: 16),
            LumiInput(
              controller: emailController,
              label: 'Email',
              hintText: 'your.email@example.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 8),
            LumiPasswordInput(
              controller: passwordController,
              label: 'Password',
              hintText: 'Min 8 chars, mixed case + number',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final email = emailController.text.trim();
              final password = passwordController.text;
              if (email.isEmpty || password.isEmpty) return;

              Navigator.of(dialogContext).pop();

              setState(() => _isLoading = true);
              try {
                await TestDataSetup.createNewSchoolAdmin(
                  email: email,
                  password: password,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Admin account created for $email. Check your inbox to verify, then log in.',
                    ),
                    duration: const Duration(seconds: 8),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // Lumi Mascot (long-press reveals DEV-only surface)
                Center(
                  child: Animate(
                    effects: const [
                      FadeEffect(duration: Duration(milliseconds: 500)),
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
                            instance.onLongPress = _handleDevAccessGesture;
                          },
                        ),
                      },
                      child: const LumiMascot(
                        variant: LumiVariant.login,
                        size: 120,
                        message: 'Welcome back!',
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title
                Text(
                  'Log In',
                  style: LumiType.displayL,
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'Enter your credentials to continue',
                  style: LumiType.body.copyWith(color: LumiTokens.muted),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

                const SizedBox(height: 32),

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: LumiTokens.red.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusSmall),
                      border: Border.all(color: LumiTokens.red, width: 1),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: LumiTokens.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: LumiType.caption
                                .copyWith(color: LumiTokens.red),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().shake(),

                const SizedBox(height: 16),

                if (_signInMode == _SignInMode.email) ...[
                  // Email + password form
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        LumiInput(
                          controller: _emailController,
                          label: 'Email',
                          hintText: 'you@example.com',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          prefixIcon: const Icon(Icons.email_outlined),
                          validator: FormBuilderValidators.compose([
                            FormBuilderValidators.required(
                              errorText: 'Email is required',
                            ),
                            FormBuilderValidators.email(
                              errorText: 'Enter a valid email',
                            ),
                          ]),
                        ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
                        const SizedBox(height: 16),
                        LumiPasswordInput(
                          controller: _passwordController,
                          label: 'Password',
                          textInputAction: TextInputAction.done,
                          validator: FormBuilderValidators.required(
                            errorText: 'Password is required',
                          ),
                        ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  LumiPrimaryButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    text: 'Log In',
                    isLoading: _isLoading,
                    color: LumiTokens.red,
                  ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
                  const SizedBox(height: 8),
                  Center(
                    child: LumiTextButton(
                      onPressed: () => context.push('/auth/forgot-password'),
                      text: 'Forgot Password?',
                      color: LumiTokens.red,
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
                  ),
                  Center(
                    child: LumiTextButton(
                      onPressed: _isLoading ? null : _toggleSignInMode,
                      text: 'Sign in with phone instead',
                      color: LumiTokens.red,
                    ),
                  ),
                ] else ...[
                  // Phone-primary sub-form
                  LumiInput(
                    controller: _phoneController,
                    label: 'Mobile number',
                    hintText: '0400 000 000',
                    helperText: 'Australian mobile only.',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\s]')),
                    ],
                    enabled:
                        _phoneStage == _PhoneStage.enterNumber && !_isLoading,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_phoneStage == _PhoneStage.enterCode) ...[
                    const SizedBox(height: 16),
                    LumiInput(
                      controller: _phoneSmsController,
                      label: '6-digit code',
                      hintText: '123456',
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      prefixIcon: const Icon(Icons.sms_outlined),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) {
                        setState(() {});
                        if (_smsCodeValid && !_isLoading) _verifyPhoneLogin();
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  LumiPrimaryButton(
                    onPressed: _isLoading
                        ? null
                        : (_phoneStage == _PhoneStage.enterNumber
                            ? (_phoneValid ? _sendPhoneLoginCode : null)
                            : (_smsCodeValid ? _verifyPhoneLogin : null)),
                    text: _phoneStage == _PhoneStage.enterNumber
                        ? 'Send code'
                        : 'Verify & sign in',
                    isLoading: _isLoading,
                    color: LumiTokens.red,
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: LumiTextButton(
                      onPressed: _isLoading ? null : _toggleSignInMode,
                      text: 'Use email and password instead',
                      color: LumiTokens.red,
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // "New to Lumi?" section divider
                Row(
                  children: [
                    const Expanded(child: Divider(color: LumiTokens.rule)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('New to Lumi?', style: LumiType.caption),
                    ),
                    const Expanded(child: Divider(color: LumiTokens.rule)),
                  ],
                ).animate().fadeIn(delay: 800.ms, duration: 500.ms),

                const SizedBox(height: 16),

                // Role picker: three cards in a row, one per audience
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _RegisterRoleCard(
                          icon: Icons.family_restroom,
                          title: 'Parent',
                          subtitle: 'Student code',
                          accent: LumiTokens.red,
                          onTap: () => showParentRegistrationModal(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RegisterRoleCard(
                          icon: Icons.school_rounded,
                          title: 'Teacher',
                          subtitle: 'School code',
                          accent: LumiTokens.green,
                          onTap: () => showTeacherRegistrationModal(context),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _RegisterRoleCard(
                          icon: Icons.apartment_rounded,
                          title: 'School',
                          subtitle: 'Request a demo',
                          accent: LumiTokens.blue,
                          onTap: () => context.push('/onboarding/demo'),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

                if (hasDevAccess()) ...[
                  const SizedBox(height: 32),
                  // DEV ONLY: Create admin account button
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusSmall),
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
                          onPressed: () => _showCreateAdminDialog(),
                          text: 'Create Admin Account',
                          icon: Icons.admin_panel_settings,
                        ),
                        const SizedBox(height: 8),
                        LumiTextButton(
                          onPressed: () {
                            if (_firebaseService.auth.currentUser == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Sign in to your dev account first.',
                                  ),
                                ),
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
          ),
        ),
      ),
    );
  }
}

class _RegisterRoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _RegisterRoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(LumiTokens.radiusMedium);
    return Material(
      color: LumiTokens.paper,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: radius,
            border: Border.all(color: LumiTokens.rule, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style:
                      LumiType.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: LumiType.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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

  const _MfaCodeDialog({
    required this.phoneHint,
    required this.onResend,
  });

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

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.phoneHint != null && widget.phoneHint!.isNotEmpty
        ? 'Enter the 6-digit code sent to ${widget.phoneHint}.'
        : 'Enter the 6-digit code we just sent to your phone.';
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      title: const Text('Verify it\'s you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(subtitle, style: LumiType.caption),
          const SizedBox(height: 16),
          LumiInput(
            controller: _codeController,
            label: 'SMS code',
            keyboardType: TextInputType.number,
            autofocus: true,
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
                      } finally {
                        if (mounted) setState(() => _resending = false);
                      }
                    },
              child: Text(_resending ? 'Sending…' : 'Resend code',
                  style: LumiType.caption),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _codeValid
              ? () => Navigator.of(context).pop(_codeController.text.trim())
              : null,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}
