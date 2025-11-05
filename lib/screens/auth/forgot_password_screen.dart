import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/firebase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  String? _successEmail;

  Future<void> _handlePasswordReset() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final values = _formKey.currentState!.value;
      final email = values['email'] as String;

      try {
        await _firebaseService.auth.sendPasswordResetEmail(email: email);

        setState(() {
          _emailSent = true;
          _successEmail = email;
        });
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
        return 'No user found with this email address.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
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
                  child: LumiMascot(
                    mood: _emailSent ? LumiMood.celebrating : LumiMood.thinking,
                    size: 120,
                    message: _emailSent ? 'Check your email!' : "Let's help you!",
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                _emailSent ? 'Email Sent!' : 'Reset Password',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGray,
                    ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 16),

              // Description
              if (!_emailSent)
                Text(
                  "Enter your email address and we'll send you instructions to reset your password.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.gray,
                      ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              if (_emailSent) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.secondaryGreen,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.secondaryGreen,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Password reset email sent to:',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.darkGray,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _successEmail ?? '',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Please check your inbox (and spam folder) for instructions on how to reset your password.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.gray,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms).scale(),

                const SizedBox(height: 24),

                // Return to login button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: const Text('Back to Login'),
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                const SizedBox(height: 16),

                // Resend email button
                TextButton(
                  onPressed: () {
                    setState(() {
                      _emailSent = false;
                      _successEmail = null;
                    });
                  },
                  child: const Text("Didn't receive the email? Try again"),
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
              ],

              if (!_emailSent) ...[
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

                // Email form
                FormBuilder(
                  key: _formKey,
                  child: FormBuilderTextField(
                    name: 'email',
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'Enter your registered email',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(
                        errorText: 'Email is required',
                      ),
                      FormBuilderValidators.email(
                        errorText: 'Enter a valid email',
                      ),
                    ]),
                    onSubmitted: (_) => _handlePasswordReset(),
                  ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
                ),

                const SizedBox(height: 32),

                // Submit button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handlePasswordReset,
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
                      : const Text('Send Reset Email'),
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                const SizedBox(height: 24),

                // Additional help
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.info,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need help?',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.info,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'If you continue to have trouble, please contact your school administrator.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.darkGray,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
              ],
            ],
          ),
        ),
      ),
    );
  }
}