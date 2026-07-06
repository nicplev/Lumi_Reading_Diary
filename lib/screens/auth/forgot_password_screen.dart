import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_input.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/firebase_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseService _firebaseService = FirebaseService.instance;
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  String? _successEmail;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordReset() async {
    if (_formKey.currentState?.validate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final email = _emailController.text.trim();

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
        return 'No account found for this email. If you signed up with a phone '
            'number, go back and use "Log in with phone" — password reset only '
            'works for email accounts.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: LumiTokens.ink),
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
                  child: _emailSent
                      ? const LumiMascot(
                          variant: LumiVariant.promo,
                          size: 120,
                          message: 'Check your email!',
                        )
                      : Image.asset(
                          'assets/UI Lumi/password+lock.png',
                          height: 132,
                          fit: BoxFit.contain,
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                _emailSent ? 'Email Sent!' : 'Reset Password',
                style: LumiType.heading.copyWith(fontSize: 32),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              const SizedBox(height: 16),

              // Description
              if (!_emailSent)
                Text(
                  "Enter your email address and we'll send you instructions to reset your password.",
                  style: LumiType.body.copyWith(color: LumiTokens.muted),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              if (_emailSent) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: LumiTokens.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                    border: Border.all(color: LumiTokens.green, width: 1),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: LumiTokens.green,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Password reset email sent to:',
                        style: LumiType.body,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _successEmail ?? '',
                        style: LumiType.subhead.copyWith(color: LumiTokens.green),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Please check your inbox (and spam folder) for instructions on how to reset your password.',
                        style: LumiType.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms).scale(),

                const SizedBox(height: 24),

                // Return to login button
                LumiPrimaryButton(
                  onPressed: () => Navigator.pop(context),
                  text: 'Back to Login',
                  color: LumiTokens.red,
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                const SizedBox(height: 16),

                // Resend email button
                LumiTextButton(
                  onPressed: () {
                    setState(() {
                      _emailSent = false;
                      _successEmail = null;
                    });
                  },
                  text: "Didn't receive the email? Try again",
                  color: LumiTokens.red,
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
              ],

              if (!_emailSent) ...[
                const SizedBox(height: 32),

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LumiTokens.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
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
                            style: LumiType.caption.copyWith(color: LumiTokens.red),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn().shake(),

                const SizedBox(height: 16),

                // Email form
                Form(
                  key: _formKey,
                  child: LumiInput(
                    controller: _emailController,
                    hintText: 'Email Address',
                    borderless: true,
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: LumiTokens.ink),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    onSubmitted: (_) =>
                        _isLoading ? null : _handlePasswordReset(),
                    validator: FormBuilderValidators.compose([
                      FormBuilderValidators.required(
                        errorText: 'Email is required',
                      ),
                      FormBuilderValidators.email(
                        errorText: 'Enter a valid email',
                      ),
                    ]),
                  ).animate().fadeIn(delay: 400.ms, duration: 500.ms),
                ),

                const SizedBox(height: 32),

                // Submit button
                LumiPrimaryButton(
                  onPressed: _isLoading ? null : _handlePasswordReset,
                  text: 'Send Reset Email',
                  isLoading: _isLoading,
                  color: LumiTokens.red,
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                const SizedBox(height: 24),

                // Additional help
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: LumiTokens.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: LumiTokens.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need help?',
                              style: LumiType.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: LumiTokens.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'If you continue to have trouble, please contact your school administrator.',
                              style: LumiType.caption,
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
