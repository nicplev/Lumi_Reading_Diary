import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/parent_linking_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_link_code_model.dart';
import '../parent/parent_home_screen.dart';

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

      try {
        final linkCode = await _linkingService.verifyCode(code);

        if (linkCode == null) {
          throw Exception(
              'Invalid or expired code. Please check with your school.');
        }

        // Fetch student information
        final studentDoc = await _firestore
            .collection('schools')
            .doc(linkCode.schoolId)
            .collection('students')
            .doc(linkCode.studentId)
            .get();

        if (!studentDoc.exists) {
          throw Exception('Student information not found.');
        }

        setState(() {
          _verifiedCode = linkCode;
          _studentInfo = studentDoc.data();
          _currentStep = 1;
        });
      } catch (e) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
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
      final email = values['email'] as String;
      final password = values['password'] as String;
      final fullName = values['fullName'] as String;

      try {
        // 1. Create Firebase Auth user
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final userId = userCredential.user!.uid;

        // 2. Create parent user document
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

        await _firestore
            .collection('schools')
            .doc(_verifiedCode!.schoolId)
            .collection('parents')
            .doc(userId)
            .set(parentUser.toFirestore());

        // 3. Link parent to student
        await _linkingService.linkParentToStudent(
          code: _verifiedCode!.code,
          parentUserId: userId,
          parentEmail: email,
        );

        // 4. Move to success step
        setState(() {
          _currentStep = 2;
        });
      } on FirebaseAuthException catch (e) {
        setState(() {
          _errorMessage = _getAuthErrorMessage(e.code);
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to complete registration: ${e.toString()}';
        });
      } finally {
        setState(() {
          _isLoading = false;
        });
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
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Parent Registration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Progress indicator
              _buildProgressIndicator(),

              const SizedBox(height: 32),

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
                        ? AppColors.primary
                        : AppColors.lightGray,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (index < 2) const SizedBox(width: 4),
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

        const SizedBox(height: 24),

        Text(
          'Enter Your Student Code',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.darkGray,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Text(
          'You should have received an 8-character code from your child\'s school',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.gray,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // Error message
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: AppColors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error),
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
                decoration: const InputDecoration(
                  labelText: 'Student Link Code',
                  prefixIcon: Icon(Icons.qr_code),
                  hintText: 'e.g. ABC12345',
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(
                    errorText: 'Please enter the code',
                  ),
                  FormBuilderValidators.match(
                    r'^[A-Z0-9]{8}$',
                    errorText: 'Code must be 8 characters (letters and numbers)',
                  ),
                ]),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Verify Code'),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Info box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.info.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.info),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Don\'t have a code? Contact your child\'s teacher or school administrator.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                      ),
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
            mood: LumiMood.excited,
            size: 100,
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Create Your Account',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.darkGray,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Text(
          'You\'re registering for: ${_studentInfo?['firstName']} ${_studentInfo?['lastName']}',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 32),

        // Error message
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error),
            ),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error),
            ),
          ).animate().fadeIn().shake(),

        // Registration form
        FormBuilder(
          key: _registrationFormKey,
          child: Column(
            children: [
              FormBuilderTextField(
                name: 'fullName',
                decoration: const InputDecoration(
                  labelText: 'Your Full Name *',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: FormBuilderValidators.required(),
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 16),

              FormBuilderTextField(
                name: 'email',
                decoration: const InputDecoration(
                  labelText: 'Email Address *',
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                  FormBuilderValidators.email(),
                ]),
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              const SizedBox(height: 16),

              FormBuilderTextField(
                name: 'password',
                decoration: const InputDecoration(
                  labelText: 'Password *',
                  prefixIcon: Icon(Icons.lock),
                  hintText: 'At least 8 characters',
                ),
                obscureText: true,
                validator: FormBuilderValidators.compose([
                  FormBuilderValidators.required(),
                  FormBuilderValidators.minLength(8),
                ]),
              ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

              const SizedBox(height: 16),

              FormBuilderTextField(
                name: 'passwordConfirm',
                decoration: const InputDecoration(
                  labelText: 'Confirm Password *',
                  prefixIcon: Icon(Icons.lock_outline),
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

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _isLoading ? null : _completeRegistration,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Create Account & Link Student'),
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

        const SizedBox(height: 32),

        Text(
          'You\'re All Set!',
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),

        Text(
          'Your account has been created and linked to ${_studentInfo?['firstName']} ${_studentInfo?['lastName']}.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.gray,
              ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 48),

        ElevatedButton(
          onPressed: () {
            // Navigate to parent home screen
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder: (context) => const ParentHomeScreen(
                  user: null, // Will be loaded from auth
                ),
              ),
              (route) => false,
            );
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          child: const Text('Start Logging Reading'),
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.success.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'You can now log reading minutes, track progress, and stay connected with your child\'s teacher!',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.success,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
