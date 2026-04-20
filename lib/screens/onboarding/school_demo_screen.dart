import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_step_indicator.dart';
import '../../core/widgets/lumi_mascot.dart';
import 'demo_request_screen.dart';

class SchoolDemoScreen extends StatefulWidget {
  const SchoolDemoScreen({super.key});

  @override
  State<SchoolDemoScreen> createState() => _SchoolDemoScreenState();
}

class _SchoolDemoScreenState extends State<SchoolDemoScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // One distinct book-colour for each slide so the header mascot shifts hue
  // as the user progresses through the flow.
  static const List<String> _bookAssets = [
    'assets/lumi/Lumi_Books_Pink.png',
    'assets/lumi/Lumi_Books_Green.png',
    'assets/lumi/Lumi_Books_LBlue.png',
    'assets/lumi/Lumi_Books_Orange.png',
    'assets/lumi/Lumi_Books_Yellow.png',
    'assets/lumi/Lumi_Books_Purple.png',
  ];

  final List<_DemoSlide> _slides = [
    _DemoSlide(
      title: 'Welcome to Lumi',
      subtitle: 'Your Complete Reading Tracking Solution',
      description:
          'Lumi helps schools, teachers, and parents work together to nurture a love of reading in every child.',
      heroVariant: LumiVariant.login,
      color: AppColors.rosePink,
    ),
    _DemoSlide(
      title: 'For Teachers',
      subtitle: 'Effortless Reading Management',
      description:
          'Create smart allocations, monitor progress in real-time, and celebrate achievements with your class.',
      features: [
        _DemoFeature('Real-time class dashboard'),
        _DemoFeature('Smart reading allocations'),
        _DemoFeature('Individual student tracking'),
        _DemoFeature('CSV export & reports'),
        _DemoFeature('Parent communication'),
      ],
      heroVariant: LumiVariant.teacher,
      color: AppColors.mintGreen,
    ),
    _DemoSlide(
      title: 'For Parents',
      subtitle: 'Simple, Engaging, Motivating',
      description:
          'Log reading with one tap, track progress, and watch your child\'s reading journey unfold.',
      features: [
        _DemoFeature('One-tap reading logs'),
        _DemoFeature('Visual progress tracking'),
        _DemoFeature('Reading streak motivation'),
        _DemoFeature('Offline support'),
        _DemoFeature('Daily reminders'),
      ],
      heroVariant: LumiVariant.parent,
      color: AppColors.skyBlue,
    ),
    _DemoSlide(
      title: 'For Schools',
      subtitle: 'Comprehensive Administration',
      description:
          'Manage your entire school\'s reading program from one central dashboard.',
      features: [
        _DemoFeature('School-wide analytics'),
        _DemoFeature('Teacher & parent management'),
        _DemoFeature('Custom reading levels'),
        _DemoFeature('Subscription handling'),
        _DemoFeature('Data export & reports'),
      ],
      heroVariant: LumiVariant.school,
      color: AppColors.warmOrange,
    ),
    _DemoSlide(
      title: 'Seamless Parent Linking',
      subtitle: 'Connect Families Instantly',
      description:
          'Generate unique codes for each student. Parents register and link instantly - no manual setup needed.',
      features: [
        _DemoFeature('Unique student codes'),
        _DemoFeature('Instant parent verification'),
        _DemoFeature('Secure linking protocol'),
        _DemoFeature('Multiple parent support'),
        _DemoFeature('Easy unlinking options'),
      ],
      heroVariant: LumiVariant.linking,
      color: AppColors.darkYellow,
    ),
    _DemoSlide(
      title: 'Key Benefits',
      subtitle: 'Why Schools Choose Lumi',
      description: '',
      features: [
        _DemoFeature('Real-time data & insights', icon: Icons.insights),
        _DemoFeature('Increased reading engagement', icon: Icons.gps_fixed),
        _DemoFeature('Works offline everywhere', icon: Icons.phone_android),
        _DemoFeature('Secure & GDPR compliant', icon: Icons.lock_outline),
        _DemoFeature('Quick 15-minute setup', icon: Icons.bolt),
        _DemoFeature('Excellent support', icon: Icons.support_agent),
      ],
      heroVariant: LumiVariant.promo,
      color: AppColors.rosePink,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Navigate to demo request form
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const DemoRequestScreen(),
        ),
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: LumiPadding.allS,
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: animation, child: child),
                    ),
                    child: Image.asset(
                      _bookAssets[_currentPage % _bookAssets.length],
                      key: ValueKey<int>(_currentPage % _bookAssets.length),
                      width: 36,
                      height: 36,
                      fit: BoxFit.contain,
                    ),
                  ),
                  LumiGap.horizontalXS,
                  Expanded(
                    child: Text(
                      'Lumi Reading Diary',
                      style: LumiTextStyles.h3(color: AppColors.rosePink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  LumiTextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DemoRequestScreen(),
                        ),
                      );
                    },
                    text: 'Skip',
                    icon: Icons.arrow_forward,
                  ),
                ],
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  return _buildSlide(_slides[index]);
                },
              ),
            ),

            // Page indicators
            Padding(
              padding: LumiPadding.verticalS,
              child: Center(
                child: LumiStepIndicator(
                  stepCount: _slides.length,
                  currentStep: _currentPage,
                ),
              ),
            ),

            // Navigation buttons — constrained width so on tablets/desktop
            // the CTAs don't stretch edge-to-edge.
            Padding(
              padding: LumiPadding.allM,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Row(
                    children: [
                      if (_currentPage > 0)
                        Expanded(
                          child: LumiSecondaryButton(
                            onPressed: _previousPage,
                            text: 'Previous',
                            isFullWidth: true,
                          ),
                        ),
                      if (_currentPage > 0) LumiGap.horizontalS,
                      Expanded(
                        flex: 2,
                        child: LumiPrimaryButton(
                          onPressed: _nextPage,
                          text: _currentPage == _slides.length - 1
                              ? 'Get Started'
                              : 'Next',
                          isFullWidth: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_DemoSlide slide) {
    final size = MediaQuery.of(context).size;
    final hasFeatures = slide.features != null && slide.features!.isNotEmpty;
    // Size the hero responsively from available viewport height, then cap by
    // width so it never stretches past a comfortable fraction of the screen.
    // Feature slides get a smaller hero so benefit chips sit in the initial
    // viewport without scrolling; intro/summary slides get a larger hero.
    final heightBudget = hasFeatures ? size.height * 0.22 : size.height * 0.42;
    final widthCap = size.width * 0.85;
    final heroBounds = hasFeatures
        ? const (min: 140.0, max: 240.0)
        : const (min: 220.0, max: 400.0);
    final heroSize = math
        .min(heightBudget, widthCap)
        .clamp(heroBounds.min, heroBounds.max);

    // Constrain slide content to a reading-friendly width on tablets/desktops
    // so text lines don't stretch uncomfortably wide.
    final contentMaxWidth = math.min(size.width, 560.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        LumiSpacing.m,
        0,
        LumiSpacing.m,
        LumiSpacing.m,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
          // Hero illustration with a subtle tinted halo so the image feels
          // grounded rather than floating on the off-white background.
          Container(
            width: heroSize,
            height: heroSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  slide.color.withValues(alpha: 0.12),
                  slide.color.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Image.asset(
              slide.heroVariant.asset,
              fit: BoxFit.contain,
            ),
          ).animate().fadeIn(duration: 400.ms).scale(
                begin: const Offset(0.92, 0.92),
                end: const Offset(1, 1),
                duration: 500.ms,
                curve: Curves.easeOutBack,
              ),

          LumiGap.s,

          // Title
          Text(
            slide.title,
            style: LumiTextStyles.displayMedium(color: AppColors.charcoal),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

          LumiGap.xxs,

          // Subtitle
          Text(
            slide.subtitle,
            style: LumiTextStyles.h3(color: slide.color),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

          if (slide.description.isNotEmpty) ...[
            LumiGap.s,
            Text(
              slide.description,
              style: LumiTextStyles.bodyMedium(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 500.ms, duration: 500.ms),
          ],

          if (hasFeatures) LumiGap.m,

          // Features — tight compact rows so the full list is visible without
          // scrolling on a standard phone viewport.
          if (hasFeatures)
            ...slide.features!.asMap().entries.map((entry) {
              final index = entry.key;
              final feature = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: LumiSpacing.xxs),
                padding: const EdgeInsets.symmetric(
                  horizontal: LumiSpacing.s,
                  vertical: LumiSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: LumiBorders.medium,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: slide.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        feature.icon ?? Icons.check,
                        color: slide.color,
                        size: 14,
                      ),
                    ),
                    LumiGap.horizontalS,
                    Expanded(
                      child: Text(
                        feature.text,
                        style: LumiTextStyles.bodyMedium(
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: (500 + (index * 60)).ms, duration: 400.ms)
                  .slideX(begin: 0.15, end: 0);
            }),
            ],
          ),
        ),
      ),
    );
  }
}

class _DemoSlide {
  final String title;
  final String subtitle;
  final String description;
  final List<_DemoFeature>? features;
  final LumiVariant heroVariant;
  final Color color;

  _DemoSlide({
    required this.title,
    required this.subtitle,
    required this.description,
    this.features,
    required this.heroVariant,
    required this.color,
  });
}

class _DemoFeature {
  final String text;
  final IconData? icon;
  const _DemoFeature(this.text, {this.icon});
}
