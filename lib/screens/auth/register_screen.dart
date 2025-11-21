import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';

class RegisterScreen extends StatefulWidget {
  final String? inviteCode;
  final String? schoolId;

  const RegisterScreen({
    super.key,
    this.inviteCode,
    this.schoolId,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  UserRole _selectedRole = UserRole.parent;

  Future<void> _handleRegister() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final values = _formKey.currentState!.value;
      final email = values['email'] as String;
      final password = values['password'] as String;
      final fullName = values['fullName'] as String;

      try {
        // Create user with email and password
        final UserCredential userCredential = await _firebaseService.auth
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null) {
          // Update display name
          await userCredential.user!.updateDisplayName(fullName);

          // Create user document in Firestore
          final user = UserModel(
            id: userCredential.user!.uid,
            email: email,
            fullName: fullName,
            role: _selectedRole,
            schoolId: widget.schoolId,
            createdAt: DateTime.now(),
            lastLoginAt: DateTime.now(),
          );

          await _firebaseService.firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .set(user.toFirestore());

          // If there's an invite code, link the parent to children
          if (widget.inviteCode != null && _selectedRole == UserRole.parent) {
            await _linkParentWithInviteCode(
              userCredential.user!.uid,
              widget.inviteCode!,
            );
          }

          if (!mounted) return;

          // Navigate to appropriate home screen
          if (_selectedRole == UserRole.parent) {
            final homeRoute = AppRouter.getHomeRouteForRole(user.role);
            context.go(homeRoute, extra: user);
          } else {
            // For teacher or admin, show pending approval screen
            _showPendingApprovalDialog();
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

  Future<void> _linkParentWithInviteCode(String parentId, String inviteCode) async {
    try {
      // Find students linked to this invite code
      final querySnapshot = await _firebaseService.firestore
          .collection('invites')
          .where('code', isEqualTo: inviteCode)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final invite = querySnapshot.docs.first;
        final studentIds = List<String>.from(invite.data()['studentIds'] ?? []);

        // Link parent to students
        await _firebaseService.firestore
            .collection('users')
            .doc(parentId)
            .update({
          'linkedChildren': studentIds,
        });

        // Add parent to each student
        for (String studentId in studentIds) {
          await _firebaseService.firestore
              .collection('students')
              .doc(studentId)
              .update({
            'parentIds': FieldValue.arrayUnion([parentId]),
          });
        }

        // Mark invite as used
        await invite.reference.update({
          'usedBy': parentId,
          'usedAt': FieldValue.serverTimestamp(),
          'isActive': false,
        });
      }
    } catch (e) {
      debugPrint('Error linking parent with invite code: $e');
    }
  }

  void _showPendingApprovalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Registration Successful'),
        content: const Text(
          'Your account has been created successfully. '
          'Please wait for school admin approval to access the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.go('/auth/login'),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.darkGray),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Lumi Mascot
              Center(
                child: Animate(
                  effects: const [
                    FadeEffect(duration: Duration(milliseconds: 500)),
                  ],
                  child: const LumiMascot(
                    mood: LumiMood.happy,
                    size: 100,
                    message: 'Join Lumi!',
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Create Account',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGray,
                    ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 32),

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                              ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shake(),

              const SizedBox(height: 16),

              // Role Selection
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I am a...',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _RoleCard(
                            role: UserRole.parent,
                            isSelected: _selectedRole == UserRole.parent,
                            onTap: () => setState(() {
                              _selectedRole = UserRole.parent;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _RoleCard(
                            role: UserRole.teacher,
                            isSelected: _selectedRole == UserRole.teacher,
                            onTap: () => setState(() {
                              _selectedRole = UserRole.teacher;
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              const SizedBox(height: 16),

              // Registration Form
              FormBuilder(
                key: _formKey,
                child: Column(
                  children: [
                    // Full name field
                    FormBuilderTextField(
                      name: 'fullName',
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(
                          errorText: 'Name is required',
                        ),
                        FormBuilderValidators.minLength(
                          2,
                          errorText: 'Name must be at least 2 characters',
                        ),
                      ]),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    const SizedBox(height: 16),

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
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                    const SizedBox(height: 16),

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
                            color: AppColors.gray,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(
                          errorText: 'Password is required',
                        ),
                        FormBuilderValidators.minLength(
                          6,
                          errorText: 'Password must be at least 6 characters',
                        ),
                      ]),
                    ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                    const SizedBox(height: 16),

                    // Confirm password field
                    FormBuilderTextField(
                      name: 'confirmPassword',
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.gray,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (_formKey.currentState?.fields['password']?.value != value) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      onSubmitted: (_) => _handleRegister(),
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

                    if (widget.inviteCode != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.secondaryGreen,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_outline,
                              color: AppColors.secondaryGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Invite code: ${widget.inviteCode}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.secondaryGreen,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Register button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleRegister,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.white,
                          ),
                        ),
                      )
                    : const Text('Create Account'),
              ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

              const SizedBox(height: 24),

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray,
                        ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                    ),
                    child: const Text('Log In'),
                  ),
                ],
              ).animate().fadeIn(delay: 1000.ms, duration: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final UserRole role;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final roleInfo = _getRoleInfo(role);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? roleInfo['color'].withOpacity(0.1) : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? roleInfo['color'] : AppColors.lightGray,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              roleInfo['icon'],
              color: isSelected ? roleInfo['color'] : AppColors.gray,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              roleInfo['title'],
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: isSelected ? roleInfo['color'] : AppColors.darkGray,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getRoleInfo(UserRole role) {
    switch (role) {
      case UserRole.parent:
        return {
          'title': 'Parent',
          'icon': Icons.family_restroom,
          'color': AppColors.parentColor,
        };
      case UserRole.teacher:
        return {
          'title': 'Teacher',
          'icon': Icons.school,
          'color': AppColors.teacherColor,
        };
      case UserRole.schoolAdmin:
        return {
          'title': 'Admin',
          'icon': Icons.admin_panel_settings,
          'color': AppColors.adminColor,
        };
    }
  }
}