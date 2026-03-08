import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../core/services/user_school_index_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: LumiPadding.allM,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LumiGap.l,

              // Lumi Mascot
              Center(
                child: Animate(
                  effects: const [
                    FadeEffect(duration: Duration(milliseconds: 500)),
                  ],
                  child: const LumiMascot(
                    mood: LumiMood.waving,
                    size: 120,
                    message: 'Welcome back!',
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

              LumiGap.s,

              // Forgot password link
              Align(
                alignment: Alignment.centerRight,
                child: LumiTextButton(
                  onPressed: () => context.push('/auth/forgot-password'),
                  text: 'Forgot Password?',
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
              ),

              LumiGap.m,

              // Login button
              LumiPrimaryButton(
                onPressed: _isLoading ? null : _handleLogin,
                text: 'Log In',
                isLoading: _isLoading,
              ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

              LumiGap.m,

              // Register link
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  Text(
                    'Teacher account needed?',
                    style: LumiTextStyles.body().copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  LumiTextButton(
                    onPressed: () => context.push('/auth/register'),
                    text: 'Register with School Code',
                  ),
                ],
              ).animate().fadeIn(delay: 800.ms, duration: 500.ms),

              LumiGap.s,

              // Invite code option for parents
              LumiTextButton(
                onPressed: () => context.push('/auth/parent-register'),
                text: 'Parent? Register with Student Code',
                icon: Icons.qr_code,
              ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

              LumiGap.xs,

              // School registration option
              LumiTextButton(
                onPressed: () => context.push('/onboarding/demo'),
                text: 'School? Request a Demo',
                icon: Icons.school,
              ).animate().fadeIn(delay: 1000.ms, duration: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}
