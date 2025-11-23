import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/onboarding_service.dart';
import '../../data/models/school_model.dart';

class SchoolRegistrationWizard extends StatefulWidget {
  final String onboardingId;

  const SchoolRegistrationWizard({
    super.key,
    required this.onboardingId,
  });

  @override
  State<SchoolRegistrationWizard> createState() =>
      _SchoolRegistrationWizardState();
}

class _SchoolRegistrationWizardState extends State<SchoolRegistrationWizard> {
  final PageController _pageController = PageController();
  final OnboardingService _onboardingService = OnboardingService();

  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Form keys for each step
  final _schoolInfoFormKey = GlobalKey<FormBuilderState>();
  final _adminAccountFormKey = GlobalKey<FormBuilderState>();
  final _readingLevelsFormKey = GlobalKey<FormBuilderState>();

  // Data collection
  Map<String, dynamic> _schoolData = {};
  Map<String, dynamic> _adminData = {};

  final List<String> _steps = [
    'School Info',
    'Admin Account',
    'Reading Levels',
    'Complete',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _nextStep() async {
    setState(() {
      _errorMessage = null;
    });

    // Validate current step
    bool isValid = false;
    switch (_currentStep) {
      case 0:
        isValid = _schoolInfoFormKey.currentState?.saveAndValidate() ?? false;
        if (isValid) {
          _schoolData = _schoolInfoFormKey.currentState!.value;
        }
        break;
      case 1:
        isValid = _adminAccountFormKey.currentState?.saveAndValidate() ?? false;
        if (isValid) {
          _adminData = _adminAccountFormKey.currentState!.value;
          // Create school and admin account
          await _createSchoolAndAdmin();
          return; // _createSchoolAndAdmin handles navigation
        }
        break;
      case 2:
        isValid = _readingLevelsFormKey.currentState?.saveAndValidate() ?? false;
        if (isValid) {
          await _completeOnboarding();
          return; // _completeOnboarding handles navigation
        }
        break;
    }

    if (isValid && _currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _createSchoolAndAdmin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _onboardingService.createSchoolAndAdmin(
        onboardingId: widget.onboardingId,
        schoolName: _schoolData['schoolName'] as String,
        adminEmail: _adminData['adminEmail'] as String,
        adminPassword: _adminData['adminPassword'] as String,
        adminFullName: _adminData['adminFullName'] as String,
        levelSchema: ReadingLevelSchema.aToZ, // Will be set in next step
        address: _schoolData['address'] as String?,
        contactEmail: _schoolData['contactEmail'] as String?,
        contactPhone: _schoolData['contactPhone'] as String?,
      );

      // Move to next step
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create account: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Complete onboarding
      await _onboardingService.completeOnboarding(widget.onboardingId);

      // Move to final step
      setState(() {
        _currentStep++;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to complete setup: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('School Registration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            _buildProgressIndicator(),

            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildSchoolInfoStep(),
                  _buildAdminAccountStep(),
                  _buildReadingLevelsStep(),
                  _buildCompletionStep(),
                ],
              ),
            ),

            // Navigation buttons
            if (_currentStep < 3) _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: LumiPadding.allM,
      child: Column(
        children: [
          Row(
            children: List.generate(_steps.length, (index) {
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
                              : AppColors.lightGray,
                          borderRadius: LumiBorders.small,
                        ),
                      ),
                    ),
                    if (index < _steps.length - 1) const SizedBox(width: 4),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(_steps.length, (index) {
              final isCurrent = index == _currentStep;
              return Expanded(
                child: Text(
                  _steps[index],
                  style: LumiTextStyles.bodySmall()?.copyWith(
                        color: isCurrent ? AppColors.rosePink : AppColors.charcoal.withValues(alpha: 0.6),
                        fontWeight:
                            isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                  textAlign: TextAlign.center,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSchoolInfoStep() {
    return SingleChildScrollView(
      padding: LumiPadding.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: LumiMascot(
              mood: LumiMood.reading,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'School Information',
            style: LumiTextStyles.h2()?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'Tell us about your school',
            style: LumiTextStyles.body()?.copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.l,
          FormBuilder(
            key: _schoolInfoFormKey,
            child: Column(
              children: [
                FormBuilderTextField(
                  name: 'schoolName',
                  decoration: const InputDecoration(
                    labelText: 'School Name *',
                    prefixIcon: Icon(Icons.school),
                  ),
                  validator: FormBuilderValidators.required(),
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'address',
                  decoration: const InputDecoration(
                    labelText: 'School Address',
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'contactEmail',
                  decoration: const InputDecoration(
                    labelText: 'School Email',
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: FormBuilderValidators.email(),
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'contactPhone',
                  decoration: const InputDecoration(
                    labelText: 'School Phone',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminAccountStep() {
    return SingleChildScrollView(
      padding: LumiPadding.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: LumiMascot(
              mood: LumiMood.happy,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'Create Admin Account',
            style: LumiTextStyles.h2()?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'This will be the main administrator account',
            style: LumiTextStyles.body()?.copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.l,
          if (_errorMessage != null)
            Container(
              padding: LumiPadding.allXS,
              margin: const EdgeInsets.only(bottom: LumiSpacing.s),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: LumiBorders.medium,
                border: Border.all(color: AppColors.error),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error)),
            ),
          FormBuilder(
            key: _adminAccountFormKey,
            child: Column(
              children: [
                FormBuilderTextField(
                  name: 'adminFullName',
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: FormBuilderValidators.required(),
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'adminEmail',
                  decoration: const InputDecoration(
                    labelText: 'Email Address *',
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.email(),
                  ]),
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'adminPassword',
                  decoration: const InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.minLength(8),
                  ]),
                ),
                LumiGap.s,
                FormBuilderTextField(
                  name: 'adminPasswordConfirm',
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password *',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value != _adminAccountFormKey
                        .currentState?.fields['adminPassword']?.value) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadingLevelsStep() {
    return SingleChildScrollView(
      padding: LumiPadding.allM,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: LumiMascot(
              mood: LumiMood.reading,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'Reading Level System',
            style: LumiTextStyles.h2()?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'Choose your preferred reading level schema',
            style: LumiTextStyles.body()?.copyWith(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
            textAlign: TextAlign.center,
          ),
          LumiGap.l,
          FormBuilder(
            key: _readingLevelsFormKey,
            child: FormBuilderRadioGroup<String>(
              name: 'levelSchema',
              decoration: const InputDecoration(
                labelText: 'Select Reading Level System *',
                border: InputBorder.none,
              ),
              validator: FormBuilderValidators.required(),
              options: [
                const FormBuilderFieldOption(
                  value: 'aToZ',
                  child: ListTile(
                    title: Text('A-Z Levels'),
                    subtitle: Text('Traditional A through Z reading levels'),
                  ),
                ),
                const FormBuilderFieldOption(
                  value: 'pmBenchmark',
                  child: ListTile(
                    title: Text('PM Benchmark'),
                    subtitle: Text('Levels 1-30'),
                  ),
                ),
                const FormBuilderFieldOption(
                  value: 'lexile',
                  child: ListTile(
                    title: Text('Lexile'),
                    subtitle: Text('BR to 1400L'),
                  ),
                ),
                const FormBuilderFieldOption(
                  value: 'custom',
                  child: ListTile(
                    title: Text('Custom'),
                    subtitle: Text('Define your own levels'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionStep() {
    return Center(
      child: Padding(
        padding: LumiPadding.allM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LumiMascot(
              mood: LumiMood.celebrating,
              size: 120,
              message: 'You\'re all set!',
            ),
            LumiGap.l,
            Text(
              'Welcome to Lumi!',
              style: LumiTextStyles.h1()?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.rosePink,
                  ),
              textAlign: TextAlign.center,
            ),
            LumiGap.s,
            Text(
              'Your school has been successfully registered. You can now start adding teachers, classes, and students.',
              style: LumiTextStyles.bodyLarge()?.copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
              textAlign: TextAlign.center,
            ),
            LumiGap.xl,
            LumiPrimaryButton(
              onPressed: () => context.go('/auth/login'),
              text: 'Continue to Login',
              isFullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: LumiPadding.allM,
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: LumiSecondaryButton(
                onPressed: _isLoading ? null : _previousStep,
                text: 'Back',
                isFullWidth: true,
              ),
            ),
          if (_currentStep > 0) LumiGap.s,
          Expanded(
            flex: 2,
            child: LumiPrimaryButton(
              onPressed: _isLoading ? null : _nextStep,
              text: _currentStep == 2 ? 'Complete Setup' : 'Continue',
              isLoading: _isLoading,
              isFullWidth: true,
            ),
          ),
        ],
      ),
    );
  }
}
