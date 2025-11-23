import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/onboarding_service.dart';
import 'school_registration_wizard.dart';

class DemoRequestScreen extends StatefulWidget {
  const DemoRequestScreen({super.key});

  @override
  State<DemoRequestScreen> createState() => _DemoRequestScreenState();
}

class _DemoRequestScreenState extends State<DemoRequestScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final OnboardingService _onboardingService = OnboardingService();
  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _referralSources = [
    'Google Search',
    'Social Media',
    'Another School',
    'Education Conference',
    'Email Marketing',
    'Other',
  ];

  Future<void> _submitRequest() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final values = _formKey.currentState!.value;

      try {
        final onboardingId = await _onboardingService.createDemoRequest(
          schoolName: values['schoolName'] as String,
          contactEmail: values['contactEmail'] as String,
          contactPhone: values['contactPhone'] as String?,
          contactPerson: values['contactPerson'] as String?,
          referralSource: values['referralSource'] as String?,
          estimatedStudentCount: int.tryParse(
                values['estimatedStudentCount'] as String? ?? '0',
              ) ??
              0,
          estimatedTeacherCount: int.tryParse(
                values['estimatedTeacherCount'] as String? ?? '0',
              ) ??
              0,
        );

        if (!mounted) return;

        // Show success message and navigate to registration wizard
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: LumiBorders.shapeLarge,
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success),
                LumiGap.horizontalXS,
                Text('Request Submitted!', style: LumiTextStyles.h3()),
              ],
            ),
            content: Text(
              'Thank you for your interest in Lumi! You can now proceed to complete your school registration.',
              style: LumiTextStyles.body(),
            ),
            actions: [
              LumiPrimaryButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SchoolRegistrationWizard(
                        onboardingId: onboardingId,
                      ),
                    ),
                  );
                },
                text: 'Continue Registration',
              ),
            ],
          ),
        );
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to submit request. Please try again.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Request Demo', style: LumiTextStyles.h2()),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: LumiPadding.allM,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mascot
              Center(
                child: Animate(
                  effects: const [
                    FadeEffect(duration: Duration(milliseconds: 500)),
                  ],
                  child: const LumiMascot(
                    mood: LumiMood.happy,
                    size: 100,
                    message: 'Let\'s get started!',
                  ),
                ),
              ),

              LumiGap.m,

              // Title
              Text(
                'Tell Us About Your School',
                style: LumiTextStyles.h1(),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms, duration: 500.ms),

              LumiGap.xs,

              Text(
                'Fill in the details below and we\'ll help you get set up',
                style: LumiTextStyles.body(color: AppColors.charcoal.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

              LumiGap.l,

              // Error message
              if (_errorMessage != null)
                Container(
                  padding: LumiPadding.allXS,
                  margin: EdgeInsets.only(bottom: LumiSpacing.s),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.small,
                    border: Border.all(color: AppColors.error, width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error),
                      LumiGap.horizontalXS,
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: LumiTextStyles.bodySmall(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().shake(),

              // Form
              FormBuilder(
                key: _formKey,
                child: Column(
                  children: [
                    // School Name
                    FormBuilderTextField(
                      name: 'schoolName',
                      decoration: const InputDecoration(
                        labelText: 'School Name *',
                        prefixIcon: Icon(Icons.school),
                      ),
                      validator: FormBuilderValidators.required(
                        errorText: 'School name is required',
                      ),
                    ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

                    LumiGap.s,

                    // Contact Person
                    FormBuilderTextField(
                      name: 'contactPerson',
                      decoration: const InputDecoration(
                        labelText: 'Your Name *',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: FormBuilderValidators.required(
                        errorText: 'Your name is required',
                      ),
                    ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

                    LumiGap.s,

                    // Email
                    FormBuilderTextField(
                      name: 'contactEmail',
                      decoration: const InputDecoration(
                        labelText: 'Email Address *',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(
                          errorText: 'Email is required',
                        ),
                        FormBuilderValidators.email(
                          errorText: 'Enter a valid email',
                        ),
                      ]),
                    ).animate().fadeIn(delay: 600.ms, duration: 500.ms),

                    LumiGap.s,

                    // Phone
                    FormBuilderTextField(
                      name: 'contactPhone',
                      decoration: const InputDecoration(
                        labelText: 'Phone Number (Optional)',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ).animate().fadeIn(delay: 700.ms, duration: 500.ms),

                    LumiGap.s,

                    // Estimated Student Count
                    FormBuilderTextField(
                      name: 'estimatedStudentCount',
                      decoration: const InputDecoration(
                        labelText: 'Estimated Number of Students',
                        prefixIcon: Icon(Icons.people),
                      ),
                      keyboardType: TextInputType.number,
                    ).animate().fadeIn(delay: 800.ms, duration: 500.ms),

                    LumiGap.s,

                    // Estimated Teacher Count
                    FormBuilderTextField(
                      name: 'estimatedTeacherCount',
                      decoration: const InputDecoration(
                        labelText: 'Estimated Number of Teachers',
                        prefixIcon: Icon(Icons.groups),
                      ),
                      keyboardType: TextInputType.number,
                    ).animate().fadeIn(delay: 900.ms, duration: 500.ms),

                    LumiGap.s,

                    // Referral Source
                    FormBuilderDropdown<String>(
                      name: 'referralSource',
                      decoration: const InputDecoration(
                        labelText: 'How did you hear about us?',
                        prefixIcon: Icon(Icons.info_outline),
                      ),
                      items: _referralSources
                          .map((source) => DropdownMenuItem(
                                value: source,
                                child: Text(source),
                              ))
                          .toList(),
                    ).animate().fadeIn(delay: 1000.ms, duration: 500.ms),

                    LumiGap.l,

                    // Submit button
                    LumiPrimaryButton(
                      onPressed: _isLoading ? null : _submitRequest,
                      text: 'Submit Request',
                      isLoading: _isLoading,
                      isFullWidth: true,
                    ).animate().fadeIn(delay: 1100.ms, duration: 500.ms),
                  ],
                ),
              ),

              LumiGap.m,

              // Info note
              Container(
                padding: LumiPadding.allS,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.1),
                  borderRadius: LumiBorders.medium,
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.info),
                    LumiGap.horizontalXS,
                    Expanded(
                      child: Text(
                        'After submitting, you\'ll proceed to complete your school setup. The process takes about 15 minutes.',
                        style: LumiTextStyles.bodySmall(color: AppColors.info),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 1200.ms, duration: 500.ms),
            ],
          ),
        ),
      ),
    );
  }
}
