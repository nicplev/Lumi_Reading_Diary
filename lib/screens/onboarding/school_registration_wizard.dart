import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_step_indicator.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../services/onboarding_service.dart';
import '../../services/analytics_service.dart';
import '../../services/crash_reporting_service.dart';
import '../../data/models/school_model.dart';

class SchoolRegistrationWizard extends StatefulWidget {
  final String onboardingId;
  final OnboardingService? onboardingService;

  const SchoolRegistrationWizard({
    super.key,
    required this.onboardingId,
    this.onboardingService,
  });

  @override
  State<SchoolRegistrationWizard> createState() =>
      _SchoolRegistrationWizardState();
}

class _SchoolRegistrationWizardState extends State<SchoolRegistrationWizard> {
  final PageController _pageController = PageController();
  late final OnboardingService _onboardingService;

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
  Map<String, dynamic> _readingLevelData = {};
  String _selectedLevelSchema = 'aToZ';

  final List<String> _steps = [
    'School Info',
    'Admin Account',
    'Reading Levels',
    'Complete',
  ];

  @override
  void initState() {
    super.initState();
    _onboardingService = widget.onboardingService ?? OnboardingService();
  }

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
        }
        break;
      case 2:
        if (_selectedLevelSchema == 'none') {
          // No validation needed for "none" — skip custom levels
          _readingLevelData = {'levelSchema': 'none'};
          isValid = true;
          await _createSchoolAndCompleteOnboarding();
          return;
        }
        isValid =
            _readingLevelsFormKey.currentState?.saveAndValidate() ?? false;
        if (isValid) {
          _readingLevelData = _readingLevelsFormKey.currentState!.value;
          await _createSchoolAndCompleteOnboarding();
          return;
        }
        break;
    }

    if (isValid && _currentStep < _steps.length - 1) {
      AnalyticsService.instance
          .logOnboardingStepCompleted(step: _steps[_currentStep]);
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

  ReadingLevelSchema _schemaFromValue(String? value) {
    switch (value) {
      case 'none':
        return ReadingLevelSchema.none;
      case 'pmBenchmark':
        return ReadingLevelSchema.pmBenchmark;
      case 'lexile':
        return ReadingLevelSchema.lexile;
      case 'numbered':
        return ReadingLevelSchema.numbered;
      case 'namedLevels':
        return ReadingLevelSchema.namedLevels;
      case 'colouredLevels':
        return ReadingLevelSchema.colouredLevels;
      case 'custom':
        return ReadingLevelSchema.custom;
      case 'aToZ':
      default:
        return ReadingLevelSchema.aToZ;
    }
  }

  List<String>? _parseCustomLevels(String? raw) {
    if (raw == null) return null;
    final values = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return values.isEmpty ? null : values;
  }

  Future<void> _createSchoolAndCompleteOnboarding() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final schema = _schemaFromValue(_readingLevelData['levelSchema'] as String?);
      final customLevels =
          _parseCustomLevels(_readingLevelData['customLevels'] as String?);

      await _onboardingService.createSchoolAndAdmin(
        onboardingId: widget.onboardingId,
        schoolName: _schoolData['schoolName'] as String,
        adminEmail: _adminData['adminEmail'] as String,
        adminPassword: _adminData['adminPassword'] as String,
        adminFullName: _adminData['adminFullName'] as String,
        levelSchema: schema,
        customLevels: customLevels,
        address: _schoolData['address'] as String?,
        contactEmail: _schoolData['contactEmail'] as String?,
        contactPhone: _schoolData['contactPhone'] as String?,
      );

      await _onboardingService.applyReadingLevelConfiguration(
        onboardingId: widget.onboardingId,
        levelSchema: schema,
        customLevels: customLevels,
      );

      await _onboardingService.completeOnboarding(widget.onboardingId);

      AnalyticsService.instance.logOnboardingStepCompleted(step: 'completed');
      CrashReportingService.instance
          .setCustomKey('onboarding_last_step', 'completed');

      setState(() {
        _currentStep = 3;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      AnalyticsService.instance
          .logOnboardingFailed(step: 'school_setup', reason: e.toString());
      CrashReportingService.instance.recordError(
        e,
        StackTrace.current,
        reason: 'School setup failed during onboarding',
      );
      setState(() {
        _errorMessage =
            'Setup could not be completed. Please review details and retry. '
            'If this keeps failing, use a different admin email and contact support.\n\n$e';
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
      backgroundColor: AppColors.offWhite,
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
    return Padding(
      padding: LumiPadding.allM,
      child: Center(
        child: LumiStepIndicator(
          stepCount: _steps.length,
          currentStep: _currentStep,
        ),
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
              variant: LumiVariant.school,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'School Information',
            style: LumiTextStyles.h2().copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'Tell us about your school',
            style: LumiTextStyles.body().copyWith(
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
              variant: LumiVariant.teacher,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'Create Admin Account',
            style: LumiTextStyles.h2().copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'This will be the main administrator account',
            style: LumiTextStyles.body().copyWith(
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
              child: Text(_errorMessage!,
                  style: const TextStyle(color: AppColors.error)),
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
                    if (value !=
                        _adminAccountFormKey
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
              variant: LumiVariant.school,
              size: 80,
            ),
          ),
          LumiGap.m,
          Text(
            'Reading Level System',
            style: LumiTextStyles.h2().copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
            textAlign: TextAlign.center,
          ),
          LumiGap.xs,
          Text(
            'Choose your preferred reading level schema',
            style: LumiTextStyles.body().copyWith(
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
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          FormBuilder(
            key: _readingLevelsFormKey,
            child: Column(
              children: [
                FormBuilderRadioGroup<String>(
                  name: 'levelSchema',
                  initialValue: _selectedLevelSchema,
                  decoration: const InputDecoration(
                    labelText: 'Select Reading Level System *',
                    border: InputBorder.none,
                  ),
                  validator: FormBuilderValidators.required(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedLevelSchema = value);
                  },
                  options: [
                    const FormBuilderFieldOption(
                      value: 'none',
                      child: ListTile(
                        title: Text('No reading levels'),
                        subtitle: Text(
                          "Students won't be assigned reading levels. You can enable levels later in school settings.",
                        ),
                      ),
                    ),
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
                      value: 'numbered',
                      child: ListTile(
                        title: Text('Numbered 1-100'),
                        subtitle: Text('Simple numbered levels from 1 to 100'),
                      ),
                    ),
                    const FormBuilderFieldOption(
                      value: 'namedLevels',
                      child: ListTile(
                        title: Text('Named Levels'),
                        subtitle: Text('Define your own named levels'),
                      ),
                    ),
                    const FormBuilderFieldOption(
                      value: 'colouredLevels',
                      child: ListTile(
                        title: Text('Colour Levels'),
                        subtitle: Text('Named levels with custom colours'),
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
                if (_selectedLevelSchema == 'custom' ||
                    _selectedLevelSchema == 'namedLevels' ||
                    _selectedLevelSchema == 'colouredLevels') ...[
                  LumiGap.s,
                  FormBuilderTextField(
                    name: 'customLevels',
                    decoration: InputDecoration(
                      labelText: _selectedLevelSchema == 'colouredLevels'
                          ? 'Level Names (comma separated) *'
                          : 'Custom Levels (comma separated) *',
                      hintText: 'e.g. Blue, Green, Orange, Purple',
                      prefixIcon: const Icon(Icons.tune),
                    ),
                    validator: (valueCandidate) {
                      if (_selectedLevelSchema != 'custom' &&
                          _selectedLevelSchema != 'namedLevels' &&
                          _selectedLevelSchema != 'colouredLevels') {
                        return null;
                      }
                      final raw = valueCandidate?.trim() ?? '';
                      if (raw.isEmpty) {
                        return 'Please enter at least one level name';
                      }
                      final parsed = _parseCustomLevels(raw) ?? [];
                      if (parsed.isEmpty) {
                        return 'Please enter valid comma-separated level names';
                      }
                      return null;
                    },
                  ),
                ],
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
              variant: LumiVariant.promo,
              size: 120,
              message: 'You\'re all set!',
            ),
            LumiGap.l,
            Text(
              'Welcome to Lumi!',
              style: LumiTextStyles.h1().copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.rosePink,
              ),
              textAlign: TextAlign.center,
            ),
            LumiGap.s,
            Text(
              'Your school setup is active. Next: import students, generate parent link codes, and share the CSV with families.',
              style: LumiTextStyles.bodyLarge().copyWith(
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
              text: _currentStep == 2 ? 'Finish' : 'Continue',
              icon: _currentStep == 2 ? Icons.check_circle : null,
              isLoading: _isLoading,
              isFullWidth: true,
            ),
          ),
        ],
      ),
    );
  }
}
