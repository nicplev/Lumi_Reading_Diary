import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
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
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.charcoal),
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
                  child: LumiMascot(
                    mood: _emailSent ? LumiMood.celebrating : LumiMood.thinking,
                    size: 120,
                    message: _emailSent ? 'Check your email!' : "Let's help you!",
                  ),
                ),
              ),

              LumiGap.l,

              // Title
              Text(
                _emailSent ? 'Email Sent!' : 'Reset Password',
                style: LumiTextStyles.h1(color: AppColors.charcoal),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              LumiGap.s,

              // Description
              if (!_emailSent)
                Text(
                  "Enter your email address and we'll send you instructions to reset your password.",
                  style: LumiTextStyles.body(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              if (_emailSent) ...[
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.medium,
                    border: Border.all(
                      color: AppColors.success,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.success,
                        size: 48,
                      ),
                      LumiGap.s,
                      Text(
                        'Password reset email sent to:',
                        style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
                      ),
                      LumiGap.xxs,
                      Text(
                        _successEmail ?? '',
                        style: LumiTextStyles.h3(color: AppColors.rosePink),
                      ),
                      LumiGap.s,
                      Text(
                        'Please check your inbox (and spam folder) for instructions on how to reset your password.',
                        style: LumiTextStyles.bodySmall(
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 300.ms, duration: 500.ms).scale(),

                LumiGap.m,

                // Return to login button
                LumiPrimaryButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  text: 'Back to Login',
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                LumiGap.s,

                // Resend email button
                LumiTextButton(
                  onPressed: () {
                    setState(() {
                      _emailSent = false;
                      _successEmail = null;
                    });
                  },
                  text: "Didn't receive the email? Try again",
                ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
              ],

              if (!_emailSent) ...[
                LumiGap.l,

                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: LumiPadding.allXS,
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

                // Email form
                FormBuilder(
                  key: _formKey,
                  child: FormBuilderTextField(
                    name: 'email',
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      labelStyle: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                      hintText: 'Enter your registered email',
                      border: OutlineInputBorder(
                        borderRadius: LumiBorders.medium,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: LumiBorders.medium,
                        borderSide: const BorderSide(
                          color: AppColors.rosePink,
                          width: 2,
                        ),
                      ),
                      errorStyle: LumiTextStyles.bodySmall(color: AppColors.error),
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

                LumiGap.l,

                // Submit button
                LumiPrimaryButton(
                  onPressed: _isLoading ? null : _handlePasswordReset,
                  text: 'Send Reset Email',
                  isLoading: _isLoading,
                ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                LumiGap.m,

                // Additional help
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.medium,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppColors.info,
                        size: 20,
                      ),
                      LumiGap.xs,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Need help?',
                              style: LumiTextStyles.label(color: AppColors.info),
                            ),
                            LumiGap.xxs,
                            Text(
                              'If you continue to have trouble, please contact your school administrator.',
                              style: LumiTextStyles.bodySmall(color: AppColors.charcoal),
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