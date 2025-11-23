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
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/school_code_service.dart';
import '../../core/services/user_school_index_service.dart';

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
  final UserSchoolIndexService _indexService = UserSchoolIndexService();
  final SchoolCodeService _schoolCodeService = SchoolCodeService();
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
        print('🔷 [REGISTER] Starting registration for: $email, role: $_selectedRole');

        // Determine school ID based on role
        late String schoolId;
        String? schoolCodeId;

        if (_selectedRole == UserRole.teacher) {
          // For teachers: Validate school code
          final schoolCode = values['schoolCode'] as String?;
          print('🔷 [REGISTER] Teacher registration - School code: $schoolCode');

          if (schoolCode == null || schoolCode.isEmpty) {
            print('❌ [REGISTER] School code is empty');
            setState(() {
              _errorMessage = 'School code is required for teachers';
            });
            return;
          }

          try {
            print('🔷 [REGISTER] Validating school code...');
            final codeDetails = await _schoolCodeService.validateSchoolCode(schoolCode);
            schoolId = codeDetails['schoolId']!;
            schoolCodeId = codeDetails['codeId'];
            print('✅ [REGISTER] School code validated! SchoolId: $schoolId, CodeId: $schoolCodeId');
          } on SchoolCodeException catch (e) {
            print('❌ [REGISTER] School code validation failed: ${e.message}');
            setState(() {
              _errorMessage = e.message;
            });
            return;
          }
        } else {
          // For parents: Use schoolId from URL parameter (if provided)
          final widgetSchoolId = widget.schoolId;
          print('🔷 [REGISTER] Parent registration - SchoolId from URL: $widgetSchoolId');

          if (widgetSchoolId == null || widgetSchoolId.isEmpty) {
            print('❌ [REGISTER] SchoolId is empty for parent');
            setState(() {
              _errorMessage = 'School ID is required. Please use the registration link provided by your school.';
            });
            return;
          }

          schoolId = widgetSchoolId;
        }

        // Create user with email and password
        print('🔷 [REGISTER] Creating Firebase Auth user...');
        final UserCredential userCredential = await _firebaseService.auth
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        print('✅ [REGISTER] Firebase Auth user created: ${userCredential.user?.uid}');

        if (userCredential.user != null) {
          // Update display name
          print('🔷 [REGISTER] Updating display name...');
          await userCredential.user!.updateDisplayName(fullName);

          // Create user document in Firestore
          final user = UserModel(
            id: userCredential.user!.uid,
            email: email,
            fullName: fullName,
            role: _selectedRole,
            schoolId: schoolId,
            createdAt: DateTime.now(),
            lastLoginAt: DateTime.now(),
          );

          // Determine the correct collection based on role
          final String collectionName = _selectedRole == UserRole.parent ? 'parents' : 'users';

          // Write to nested school structure
          print('🔷 [REGISTER] Creating Firestore document at: schools/$schoolId/$collectionName/${userCredential.user!.uid}');
          await _firebaseService.firestore
              .collection('schools')
              .doc(schoolId)
              .collection(collectionName)
              .doc(userCredential.user!.uid)
              .set(user.toFirestore());
          print('✅ [REGISTER] Firestore document created');

          // Increment appropriate counter on school document
          final counterField = _selectedRole == UserRole.parent ? 'parentCount' : 'teacherCount';
          print('🔷 [REGISTER] Incrementing $counterField on school document...');
          await _firebaseService.firestore
              .collection('schools')
              .doc(schoolId)
              .update({
            counterField: FieldValue.increment(1),
          });
          print('✅ [REGISTER] Counter incremented');

          // Create email-to-school index for fast login lookups
          print('🔷 [REGISTER] Creating user school index...');
          await _indexService.createOrUpdateIndex(
            email: email,
            schoolId: schoolId,
            userType: collectionName == 'parents' ? 'parent' : 'user',
            userId: userCredential.user!.uid,
          );
          print('✅ [REGISTER] User school index created');

          // If teacher registration, increment school code usage count
          if (_selectedRole == UserRole.teacher && schoolCodeId != null) {
            print('🔷 [REGISTER] Incrementing school code usage count...');
            await _schoolCodeService.incrementCodeUsage(schoolCodeId);
            print('✅ [REGISTER] School code usage count incremented');
          }

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
            // ignore: invalid_use_of_internal_member
            context.go(homeRoute, extra: user);
          } else {
            // For teacher or admin, show pending approval screen
            _showPendingApprovalDialog();
          }
        }
      } on FirebaseAuthException catch (e) {
        print('❌ [REGISTER] Firebase Auth Exception: ${e.code} - ${e.message}');
        setState(() {
          _errorMessage = _getErrorMessage(e.code);
        });
      } catch (e, stackTrace) {
        print('❌ [REGISTER] General Exception: $e');
        print('❌ [REGISTER] Stack trace: $stackTrace');
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
      if (widget.schoolId == null) return;

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

        // Link parent to students using nested structure
        await _firebaseService.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('parents')
            .doc(parentId)
            .update({
          'linkedChildren': studentIds,
        });

        // Add parent to each student using nested structure
        for (String studentId in studentIds) {
          await _firebaseService.firestore
              .collection('schools')
              .doc(widget.schoolId)
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
        shape: LumiBorders.shapeLarge,
        title: Text(
          'Registration Successful',
          style: LumiTextStyles.h3(),
        ),
        content: Text(
          'Your account has been created successfully. '
          'Please wait for school admin approval to access the app.',
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => context.go('/auth/login'),
            text: 'OK',
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
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.charcoal),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: LumiPadding.allM,
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

              LumiGap.m,

              // Title
              Text(
                'Create Account',
                style: LumiTextStyles.h2(),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              LumiGap.l,

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.medium,
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: AppColors.error,
                        size: 20,
                      ),
                      LumiGap.xs,
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: LumiTextStyles.bodySmall(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shake(),

              LumiGap.s,

              // Role Selection
              LumiCard(
                padding: LumiPadding.allS,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'I am a...',
                      style: LumiTextStyles.label(),
                    ),
                    LumiGap.s,
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
                        LumiGap.xs,
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

              LumiGap.s,

              // Registration Form
              FormBuilder(
                key: _formKey,
                child: Column(
                  children: [
                    // School Code field (only for teachers)
                    if (_selectedRole == UserRole.teacher) ...[
                      FormBuilderTextField(
                        name: 'schoolCode',
                        decoration: InputDecoration(
                          labelText: 'School Code',
                          labelStyle: LumiTextStyles.body(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                          prefixIcon: Icon(Icons.vpn_key_outlined, color: AppColors.charcoal),
                          hintText: 'Enter code from your school admin',
                          hintStyle: LumiTextStyles.body(
                            color: AppColors.charcoal.withValues(alpha: 0.5),
                          ),
                          helperText: 'Ask your school admin for this code',
                          helperStyle: LumiTextStyles.bodySmall(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                          border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: LumiBorders.medium,
                            borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                          ),
                          errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                        ),
                        textCapitalization: TextCapitalization.characters,
                        textInputAction: TextInputAction.next,
                        validator: FormBuilderValidators.compose([
                          FormBuilderValidators.required(
                            errorText: 'School code is required for teachers',
                          ),
                          FormBuilderValidators.minLength(
                            6,
                            errorText: 'Code must be at least 6 characters',
                          ),
                        ]),
                      ).animate().fadeIn(delay: 350.ms, duration: 500.ms),
                      LumiGap.s,
                    ],

                    // Full name field
                    FormBuilderTextField(
                      name: 'fullName',
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        labelStyle: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(Icons.person_outline, color: AppColors.charcoal),
                        border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                          borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                        ),
                        errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
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

                    LumiGap.s,

                    // Email field
                    FormBuilderTextField(
                      name: 'email',
                      decoration: InputDecoration(
                        labelText: 'Email',
                        labelStyle: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(Icons.email_outlined, color: AppColors.charcoal),
                        border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                          borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                        ),
                        errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
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

                    LumiGap.s,

                    // Password field
                    FormBuilderTextField(
                      name: 'password',
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(Icons.lock_outline, color: AppColors.charcoal),
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
                        border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                          borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                        ),
                        errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
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

                    LumiGap.s,

                    // Confirm password field
                    FormBuilderTextField(
                      name: 'confirmPassword',
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        labelStyle: LumiTextStyles.body(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                        prefixIcon: Icon(Icons.lock_outline, color: AppColors.charcoal),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: LumiBorders.medium,
                          borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                        ),
                        errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
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
                      LumiGap.s,
                      Container(
                        padding: LumiPadding.allS,
                        decoration: BoxDecoration(
                          color: AppColors.mintGreen.withValues(alpha: 0.1),
                          borderRadius: LumiBorders.medium,
                          border: Border.all(
                            color: AppColors.mintGreen,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: AppColors.mintGreen,
                              size: 20,
                            ),
                            LumiGap.xs,
                            Expanded(
                              child: Text(
                                'Invite code: ${widget.inviteCode}',
                                style: LumiTextStyles.bodySmall(color: AppColors.mintGreen),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 800.ms, duration: 500.ms),
                    ],
                  ],
                ),
              ),

              LumiGap.l,

              // Register button
              LumiPrimaryButton(
                onPressed: _isLoading ? null : _handleRegister,
                isLoading: _isLoading,
                text: 'Create Account',
                isFullWidth: true,
              ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

              LumiGap.m,

              // Login link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: LumiTextStyles.body(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  LumiTextButton(
                    onPressed: () => Navigator.pop(context),
                    text: 'Log In',
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
      borderRadius: LumiBorders.large,
      child: Container(
        padding: LumiPadding.allS,
        decoration: BoxDecoration(
          color: isSelected ? roleInfo['color'].withValues(alpha: 0.1) : AppColors.white,
          borderRadius: LumiBorders.large,
          border: Border.all(
            color: isSelected ? roleInfo['color'] : AppColors.charcoal.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              roleInfo['icon'],
              color: isSelected ? roleInfo['color'] : AppColors.charcoal.withValues(alpha: 0.7),
              size: 32,
            ),
            LumiGap.xs,
            Text(
              roleInfo['title'],
              style: LumiTextStyles.label(
                color: isSelected ? roleInfo['color'] : AppColors.charcoal,
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