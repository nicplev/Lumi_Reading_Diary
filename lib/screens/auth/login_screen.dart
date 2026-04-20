import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_access.dart';
import '../../core/services/dev_access_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
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

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final DevAccessService _devAccess = DevAccessService.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

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
    super.dispose();
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
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final values = _formKey.currentState!.value;
      final email = (values['email'] as String).trim().toLowerCase();
      final password = values['password'] as String;

      try {
        final indexService = UserSchoolIndexService();
        // Sign in with email and password
        final UserCredential userCredential =
            await _firebaseService.auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

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

            // Save FCM token to correct parent Firestore path
            if (user.role == UserRole.parent) {
              NotificationService.instance.saveTokenForUser(
                userSchoolId,
                userCredential.user!.uid,
              );
            }

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

  void _navigateToHome(UserModel user) {
    // Check if parent is trying to access web version
    final redirectRoute = AppRouter.checkParentWebAccess(user.role);
    if (redirectRoute != null) {
      context.go(redirectRoute);
      return;
    }

    // Navigate to role-based home screen
    final homeRoute = AppRouter.getHomeRouteForRole(user.role);
    // ignore: invalid_use_of_internal_member
    context.go(homeRoute, extra: user);
  }

  void _showCreateAdminDialog() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Admin Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Use a real email you can verify.',
              style: LumiTextStyles.bodySmall().copyWith(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.s,
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'your.email@example.com',
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            LumiGap.xs,
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Min 8 chars, mixed case + number',
              ),
              obscureText: true,
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
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: LumiPadding.allM,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LumiGap.l,

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

              LumiGap.l,

              // Title
              Text(
                'Log In',
                style: LumiTextStyles.display().copyWith(
                  color: AppColors.charcoal,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              LumiGap.xs,

              // Subtitle
              Text(
                'Enter your credentials to continue',
                style: LumiTextStyles.body().copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              LumiGap.l,

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.small,
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      LumiGap.horizontalXS,
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: LumiTextStyles.bodySmall().copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shake(),

              LumiGap.s,

              // Login Form
              FormBuilder(
                key: _formKey,
                child: Column(
                  children: [
                    // Email field
                    FormBuilderTextField(
                      name: 'email',
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(
                          errorText: 'Email is required',
                        ),
                        FormBuilderValidators.email(
                          errorText: 'Enter a valid email',
                        ),
                      ]),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    LumiGap.s,

                    // Password field
                    FormBuilderTextField(
                      name: 'password',
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      validator: FormBuilderValidators.required(
                        errorText: 'Password is required',
                      ),
                      onSubmitted: (_) => _handleLogin(),
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
                  ],
                ),
              ),

              LumiGap.m,

              // Login button
              LumiPrimaryButton(
                onPressed: _isLoading ? null : _handleLogin,
                text: 'Log In',
                isLoading: _isLoading,
              ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

              LumiGap.xs,

              // Forgot password link (subdued, below primary action)
              Center(
                child: LumiTextButton(
                  onPressed: () => context.push('/auth/forgot-password'),
                  text: 'Forgot Password?',
                ).animate().fadeIn(delay: 700.ms, duration: 500.ms),
              ),

              LumiGap.l,

              // "New to Lumi?" section divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.charcoal.withValues(alpha: 0.08),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'New to Lumi?',
                      style: LumiTextStyles.bodySmall().copyWith(
                        color: AppColors.charcoal.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.charcoal.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 800.ms, duration: 500.ms),

              LumiGap.s,

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
                        accent: AppColors.parentColor,
                        onTap: () => showParentRegistrationModal(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RegisterRoleCard(
                        icon: Icons.school_rounded,
                        title: 'Teacher',
                        subtitle: 'School code',
                        accent: AppColors.teacherColor,
                        onTap: () => showTeacherRegistrationModal(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _RegisterRoleCard(
                        icon: Icons.apartment_rounded,
                        title: 'School',
                        subtitle: 'Request a demo',
                        accent: AppColors.warmOrange,
                        onTap: () => context.push('/onboarding/demo'),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

              if (hasDevAccess()) ...[
                LumiGap.l,
                // DEV ONLY: Create admin account button
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.small,
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'DEV ONLY',
                        style: LumiTextStyles.bodySmall().copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      LumiGap.xs,
                      LumiTextButton(
                        onPressed: () => _showCreateAdminDialog(),
                        text: 'Create Admin Account',
                        icon: Icons.admin_panel_settings,
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
    return Material(
      color: AppColors.white,
      borderRadius: LumiBorders.medium,
      child: InkWell(
        onTap: onTap,
        borderRadius: LumiBorders.medium,
        splashColor: accent.withValues(alpha: 0.12),
        highlightColor: accent.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: LumiBorders.medium,
            border: Border.all(
              color: AppColors.charcoal.withValues(alpha: 0.1),
              width: 1,
            ),
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
                  style: LumiTextStyles.label().copyWith(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: LumiTextStyles.bodySmall().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
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
