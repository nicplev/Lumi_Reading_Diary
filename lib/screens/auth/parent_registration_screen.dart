import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/routing/app_router.dart';
import '../../services/parent_linking_service.dart';
import '../../core/services/user_school_index_service.dart';
import '../../services/analytics_service.dart';
import '../../services/crash_reporting_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_link_code_model.dart';
import '../../core/exceptions/linking_exceptions.dart';

class ParentRegistrationScreen extends StatefulWidget {
  const ParentRegistrationScreen({super.key});

  @override
  State<ParentRegistrationScreen> createState() =>
      _ParentRegistrationScreenState();
}

class _ParentRegistrationScreenState extends State<ParentRegistrationScreen> {
  final _codeFormKey = GlobalKey<FormBuilderState>();
  final _registrationFormKey = GlobalKey<FormBuilderState>();
  final ParentLinkingService _linkingService = ParentLinkingService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int _currentStep = 0; // 0: Enter code, 1: Register, 2: Success
  bool _isLoading = false;
  String? _errorMessage;
  StudentLinkCodeModel? _verifiedCode;
  Map<String, dynamic>? _studentInfo;

  Future<void> _verifyCode() async {
    if (_codeFormKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final code = _codeFormKey.currentState!.value['code'] as String;
      debugPrint('[ParentReg] Verifying code: $code');

      try {
        // Verify the code - this now throws custom exceptions
        final linkCode = await _linkingService.verifyCode(code);
        debugPrint('[ParentReg] Code verified: schoolId=${linkCode.schoolId}, studentId=${linkCode.studentId}');

        // Use student info from link code metadata
        // This avoids needing read permissions on students collection
        final studentInfo = linkCode.metadata ?? {};
        debugPrint('[ParentReg] Student metadata: $studentInfo');
        if (studentInfo.isEmpty) {
          throw Exception('Student information not found in code. The code may have been created before metadata was supported.');
        }

        setState(() {
          _verifiedCode = linkCode;
          _studentInfo = studentInfo;
          _currentStep = 1;
        });
        AnalyticsService.instance.logParentCodeVerified();
        CrashReportingService.instance
            .setCustomKey('parent_link_code_verified', true);
      } on LinkingException catch (e) {
        debugPrint('[ParentReg] LinkingException during verify: ${e.runtimeType} - ${e.userMessage}');
        setState(() {
          _errorMessage = e.userMessage;
        });
        AnalyticsService.instance
            .logParentLinkingFailed(reason: e.runtimeType.toString());
      } catch (e) {
        debugPrint('[ParentReg] Unexpected error during verify: $e (${e.runtimeType})');
        String errorDetail = e.toString().replaceAll('Exception: ', '');
        if (errorDetail.contains('permission-denied')) {
          errorDetail = 'Permission denied reading student link codes. Please contact support.';
        }
        setState(() {
          _errorMessage = errorDetail;
        });
        AnalyticsService.instance
            .logParentLinkingFailed(reason: errorDetail);
        CrashReportingService.instance.recordError(
          e,
          StackTrace.current,
          reason: 'Parent code verification failed',
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _completeRegistration() async {
    if (_registrationFormKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final values = _registrationFormKey.currentState!.value;
      final email = (values['email'] as String).trim().toLowerCase();
      final password = values['password'] as String;
      final fullName = (values['fullName'] as String).trim();

      try {
        final indexService = UserSchoolIndexService();
        String userId;
        bool isNewAccount = false;

        // 1. Try to create Firebase Auth user (with idempotency support)
        debugPrint('[ParentReg] Step 1: Creating Firebase Auth account for $email');
        try {
          final userCredential = await _auth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          userId = userCredential.user!.uid;
          isNewAccount = true;
          debugPrint('[ParentReg] Auth account created: $userId');
          // Send email verification
          await userCredential.user!.sendEmailVerification();
        } on FirebaseAuthException catch (e) {
          debugPrint('[ParentReg] Auth error: ${e.code} - ${e.message}');
          if (e.code == 'email-already-in-use') {
            // Account exists - try to sign in and resume linking
            try {
              debugPrint('[ParentReg] Account exists, attempting sign-in...');
              final userCredential = await _auth.signInWithEmailAndPassword(
                email: email,
                password: password,
              );
              userId = userCredential.user!.uid;
              debugPrint('[ParentReg] Signed in to existing account: $userId');

              // Check if this user is already fully registered
              final existingParent = await _firestore
                  .collection('schools')
                  .doc(_verifiedCode!.schoolId)
                  .collection('parents')
                  .doc(userId)
                  .get();

              if (existingParent.exists) {
                final parentData = existingParent.data()!;
                final linkedChildren =
                    List<String>.from(parentData['linkedChildren'] ?? []);

                if (linkedChildren.contains(_verifiedCode!.studentId)) {
                  // Already fully registered and linked
                  setState(() {
                    _errorMessage =
                        'You are already registered and linked to this student. Please use the login page.';
                  });
                  await _auth.signOut();
                  return;
                }
                // Parent exists but not linked to this student - continue with linking
              }
            } on FirebaseAuthException catch (signInError) {
              debugPrint('[ParentReg] Sign-in error: ${signInError.code}');
              if (signInError.code == 'wrong-password' ||
                  signInError.code == 'invalid-credential') {
                setState(() {
                  _errorMessage =
                      'This email is already registered with a different password. If this is your account, please login instead.';
                });
                return;
              }
              rethrow;
            }
          } else {
            rethrow;
          }
        }

        // 2. Create or update parent user document
        debugPrint('[ParentReg] Step 2: Creating parent document in schools/${_verifiedCode!.schoolId}/parents/$userId');
        final parentRef = _firestore
            .collection('schools')
            .doc(_verifiedCode!.schoolId)
            .collection('parents')
            .doc(userId);

        final existingDoc = await parentRef.get();
        debugPrint('[ParentReg] Parent doc exists: ${existingDoc.exists}, isNewAccount: $isNewAccount');

        if (!existingDoc.exists) {
          // Create new parent document if it doesn't exist
          final parentUser = UserModel(
            id: userId,
            email: email,
            fullName: fullName,
            role: UserRole.parent,
            schoolId: _verifiedCode!.schoolId,
            linkedChildren: [_verifiedCode!.studentId],
            createdAt: DateTime.now(),
            isActive: true,
          );

          debugPrint('[ParentReg] Writing new parent document...');
          await parentRef.set(parentUser.toFirestore());
          debugPrint('[ParentReg] Parent document created');

          // Increment parent count on school document
          debugPrint('[ParentReg] Incrementing parent count on school...');
          try {
            await _firestore
                .collection('schools')
                .doc(_verifiedCode!.schoolId)
                .update({
              'parentCount': FieldValue.increment(1),
            });
            debugPrint('[ParentReg] School parent count incremented');
          } catch (e) {
            // Non-critical — log and continue
            debugPrint('[ParentReg] Warning: Could not increment parent count: $e');
          }

          // Create email-to-school index for fast login lookups
          debugPrint('[ParentReg] Creating email-to-school index...');
          await indexService.createOrUpdateIndex(
            email: email,
            schoolId: _verifiedCode!.schoolId,
            userType: 'parent',
            userId: userId,
          );
          debugPrint('[ParentReg] Index created');
        } else if (isNewAccount) {
          // If this is a new Firebase Auth account but parent doc exists,
          // update it with the new student (edge case: account was re-created)
          debugPrint('[ParentReg] Updating existing parent document with new student link...');
          await parentRef.update({
            'fullName': fullName,
            'email': email,
            'linkedChildren': FieldValue.arrayUnion([_verifiedCode!.studentId]),
          });

          // Update email-to-school index (in case email changed)
          await indexService.createOrUpdateIndex(
            email: email,
            schoolId: _verifiedCode!.schoolId,
            userType: 'parent',
            userId: userId,
          );
        }

        // 3. Link parent to student (uses atomic transaction)
        debugPrint('[ParentReg] Step 3: Linking parent to student via transaction...');
        try {
          await _linkingService.linkParentToStudent(
            code: _verifiedCode!.code,
            parentUserId: userId,
            parentEmail: email,
          );
          debugPrint('[ParentReg] Parent linked to student successfully');
        } on AlreadyLinkedException {
          debugPrint('[ParentReg] Parent already linked — treating as success');
          // This is actually success - user is already linked
          // Proceed to success screen
        }

        // 4. Move to success step
        debugPrint('[ParentReg] Step 4: Registration complete!');
        setState(() {
          _currentStep = 2;
        });
        AnalyticsService.instance.logParentLinkingCompleted();
        CrashReportingService.instance
            .setCustomKey('parent_linking_completed', true);
      } on LinkingException catch (e) {
        debugPrint('[ParentReg] LinkingException: ${e.runtimeType} - ${e.userMessage}');
        setState(() {
          _errorMessage = e.userMessage;
        });
        AnalyticsService.instance
            .logParentLinkingFailed(reason: e.runtimeType.toString());
        await _auth.signOut();
      } on FirebaseAuthException catch (e) {
        debugPrint('[ParentReg] FirebaseAuthException: ${e.code} - ${e.message}');
        setState(() {
          _errorMessage = _getAuthErrorMessage(e.code);
        });
        AnalyticsService.instance
            .logParentLinkingFailed(reason: e.code);
        await _auth.signOut();
      } catch (e, stackTrace) {
        debugPrint('[ParentReg] Unexpected error: $e');
        debugPrint('[ParentReg] Error type: ${e.runtimeType}');
        debugPrint('[ParentReg] Stack trace: $stackTrace');

        // Show the actual error details so we can debug
        String errorDetail = e.toString();
        if (errorDetail.contains('permission-denied')) {
          errorDetail = 'Firestore permission denied. The security rules may need updating for this operation.';
        } else if (errorDetail.contains('not-found')) {
          errorDetail = 'A required document was not found in the database.';
        } else if (errorDetail.contains('unavailable')) {
          errorDetail = 'Firebase is temporarily unavailable. Check your internet connection.';
        }

        setState(() {
          _errorMessage = 'Registration error: $errorDetail';
        });
        AnalyticsService.instance
            .logParentLinkingFailed(reason: errorDetail);
        CrashReportingService.instance.recordError(
          e,
          stackTrace,
          reason: 'Parent registration linking flow failed',
        );
        // Sign out if there was an error
        try {
          await _auth.signOut();
        } catch (_) {}
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  String _getAuthErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please login instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 8 characters.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Parent Registration', style: LumiTextStyles.h3()),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: LumiPadding.allM,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress indicator
              _buildProgressIndicator(),

              LumiGap.l,

              // Content based on step
              if (_currentStep == 0) _buildCodeEntryStep(),
              if (_currentStep == 1) _buildRegistrationStep(),
              if (_currentStep == 2) _buildSuccessStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(3, (index) {
        final isCompleted = index < _currentStep;
        final isCurrent = index == _currentStep;

        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted || isCurrent
                        ? AppColors.rosePink
                        : AppColors.charcoal.withValues(alpha: 0.2),
                    borderRadius: LumiBorders.small,
                  ),
                ),
              ),
              if (index < 2) LumiGap.xxs,
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCodeEntryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: LumiMascot(
            mood: LumiMood.waving,
            size: 100,
            message: 'Welcome, Parent!',
          ),
        ),

        LumiGap.m,

        Text(
          'Enter Your Student Code',
          style: LumiTextStyles.h2(),
          textAlign: TextAlign.center,
        ),

        LumiGap.xs,

        Text(
          'You should have received an 8-character code from your child\'s school',
          style: LumiTextStyles.body(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),

        LumiGap.l,

        // Error message
        if (_errorMessage != null)
          Container(
            padding: LumiPadding.allS,
            margin: EdgeInsets.only(bottom: LumiSpacing.s),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: LumiBorders.medium,
              border: Border.all(color: AppColors.error),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                LumiGap.xs,
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: LumiTextStyles.body(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().shake(),

        // Code entry form
        FormBuilder(
          key: _codeFormKey,
          child: Column(
            children: [
              FormBuilderTextField(
                name: 'code',
                decoration: InputDecoration(
                  labelText: 'Student Link Code',
                  labelStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(Icons.qr_code, color: AppColors.charcoal),
                  hintText: 'e.g. ABC12345',
                  hintStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: LumiBorders.medium,
                    borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                  ),
                  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(
                    errorText: 'Please enter the code',
                  ),
                  FormBuilderValidators.match(
                    RegExp(r'^[A-Z0-9]{8}$'),
                    errorText:
                        'Code must be 8 characters (letters and numbers)',
                  ),
                ]),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              LumiGap.m,
              LumiPrimaryButton(
                onPressed: _isLoading ? null : _verifyCode,
                isLoading: _isLoading,
                text: 'Verify Code',
                isFullWidth: true,
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
            ],
          ),
        ),

        LumiGap.m,

        // Info box
        Container(
          padding: LumiPadding.allS,
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.1),
            borderRadius: LumiBorders.large,
            border: Border.all(
              color: AppColors.info.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.info),
              LumiGap.s,
              Expanded(
                child: Text(
                  'Don\'t have a code? Contact your child\'s teacher or school administrator.',
                  style: LumiTextStyles.bodySmall(color: AppColors.info),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
      ],
    );
  }

  Widget _buildRegistrationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: LumiMascot(
            mood: LumiMood.happy,
            size: 100,
          ),
        ),

        LumiGap.m,

        Text(
          'Create Your Account',
          style: LumiTextStyles.h2(),
          textAlign: TextAlign.center,
        ),

        LumiGap.xs,

        Text(
          'You\'re registering for: ${_studentInfo?['studentFullName']}',
          style: LumiTextStyles.body(color: AppColors.rosePink),
          textAlign: TextAlign.center,
        ),

        LumiGap.l,

        // Error message
        if (_errorMessage != null)
          Container(
            padding: LumiPadding.allS,
            margin: EdgeInsets.only(bottom: LumiSpacing.s),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: LumiBorders.medium,
              border: Border.all(color: AppColors.error),
            ),
            child: Text(
              _errorMessage!,
              style: LumiTextStyles.body(color: AppColors.error),
            ),
          ).animate().fadeIn().shake(),

        // Registration form
        FormBuilder(
          key: _registrationFormKey,
          child: Column(
            children: [
              FormBuilderTextField(
                name: 'fullName',
                decoration: InputDecoration(
                  labelText: 'Your Full Name *',
                  labelStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(Icons.person, color: AppColors.charcoal),
                  border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: LumiBorders.medium,
                    borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                  ),
                  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
                validator: FormBuilderValidators.required(),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
              LumiGap.s,
              FormBuilderTextField(
                name: 'email',
                decoration: InputDecoration(
                  labelText: 'Email Address *',
                  labelStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(Icons.email, color: AppColors.charcoal),
                  border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: LumiBorders.medium,
                    borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                  ),
                  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                  FormBuilderValidators.email(),
                ]),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
              LumiGap.s,
              FormBuilderTextField(
                name: 'password',
                decoration: InputDecoration(
                  labelText: 'Password *',
                  labelStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  prefixIcon: Icon(Icons.lock, color: AppColors.charcoal),
                  hintText: 'At least 8 characters',
                  hintStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.5),
                  ),
                  border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: LumiBorders.medium,
                    borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                  ),
                  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
                obscureText: true,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                  FormBuilderValidators.minLength(
                    8,
                    errorText: 'Password must be at least 8 characters',
                  ),
                  (value) {
                    if (value == null) return null;
                    if (!RegExp(r'[A-Z]').hasMatch(value)) {
                      return 'Password must contain at least one uppercase letter';
                    }
                    if (!RegExp(r'[a-z]').hasMatch(value)) {
                      return 'Password must contain at least one lowercase letter';
                    }
                    if (!RegExp(r'[0-9]').hasMatch(value)) {
                      return 'Password must contain at least one number';
                    }
                    return null;
                  },
                ]),
              ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
              LumiGap.s,
              FormBuilderTextField(
                name: 'passwordConfirm',
                decoration: InputDecoration(
                  labelText: 'Confirm Password *',
                  labelStyle: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  prefixIcon:
                      Icon(Icons.lock_outline, color: AppColors.charcoal),
                  border: OutlineInputBorder(borderRadius: LumiBorders.medium),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: LumiBorders.medium,
                    borderSide: BorderSide(color: AppColors.rosePink, width: 2),
                  ),
                  errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
                ),
                obscureText: true,
                validator: (value) {
                  if (value !=
                      _registrationFormKey
                          .currentState?.fields['password']?.value) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
              LumiGap.l,
              LumiPrimaryButton(
                onPressed: _isLoading ? null : _completeRegistration,
                isLoading: _isLoading,
                text: 'Create Account & Link Student',
                isFullWidth: true,
              ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      children: [
        const Center(
          child: LumiMascot(
            mood: LumiMood.celebrating,
            size: 120,
            message: 'Welcome to the Lumi family!',
          ),
        ),
        LumiGap.l,
        Text(
          'You\'re All Set!',
          style: LumiTextStyles.h1(color: AppColors.success),
          textAlign: TextAlign.center,
        ),
        LumiGap.s,
        Text(
          'Your account has been created and linked to ${_studentInfo?['studentFullName']}.',
          style: LumiTextStyles.bodyLarge(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        LumiGap.xl,
        LumiPrimaryButton(
          onPressed: () async {
            // Fetch the user data before navigating
            final userId = _auth.currentUser?.uid;
            if (userId != null) {
              final parentDoc = await _firestore
                  .collection('schools')
                  .doc(_verifiedCode!.schoolId)
                  .collection('parents')
                  .doc(userId)
                  .get();

              if (parentDoc.exists && mounted) {
                final parentUser = UserModel.fromFirestore(parentDoc);
                final homeRoute =
                    AppRouter.getHomeRouteForRole(parentUser.role);
                // ignore: invalid_use_of_internal_member
                context.go(homeRoute, extra: parentUser);
              }
            }
          },
          text: 'Start Logging Reading',
          isFullWidth: true,
        ),
        LumiGap.s,
        Container(
          padding: LumiPadding.allS,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: LumiBorders.large,
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
              LumiGap.s,
              Text(
                'You can now log reading minutes, track progress, and stay connected with your child\'s teacher!',
                style: LumiTextStyles.body(color: AppColors.success),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
