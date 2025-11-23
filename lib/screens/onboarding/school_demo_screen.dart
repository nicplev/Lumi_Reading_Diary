import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
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

  final List<_DemoSlide> _slides = [
    _DemoSlide(
      title: 'Welcome to Lumi',
      subtitle: 'Your Complete Reading Tracking Solution',
      description:
          'Lumi helps schools, teachers, and parents work together to nurture a love of reading in every child.',
      icon: Icons.auto_stories,
      color: AppColors.rosePink,
    ),
    _DemoSlide(
      title: 'For Teachers',
      subtitle: 'Effortless Reading Management',
      description:
          'Create smart allocations, monitor progress in real-time, and celebrate achievements with your class.',
      features: [
        'Real-time class dashboard',
        'Smart reading allocations',
        'Individual student tracking',
        'CSV export & reports',
        'Parent communication',
      ],
      icon: Icons.school,
      color: AppColors.mintGreen,
    ),
    _DemoSlide(
      title: 'For Parents',
      subtitle: 'Simple, Engaging, Motivating',
      description:
          'Log reading with one tap, track progress, and watch your child\'s reading journey unfold.',
      features: [
        'One-tap reading logs',
        'Visual progress tracking',
        'Reading streak motivation',
        'Offline support',
        'Daily reminders',
      ],
      icon: Icons.family_restroom,
      color: AppColors.skyBlue,
    ),
    _DemoSlide(
      title: 'For Schools',
      subtitle: 'Comprehensive Administration',
      description:
          'Manage your entire school\'s reading program from one central dashboard.',
      features: [
        'School-wide analytics',
        'Teacher & parent management',
        'Custom reading levels',
        'Subscription handling',
        'Data export & reports',
      ],
      icon: Icons.business,
      color: AppColors.warmOrange,
    ),
    _DemoSlide(
      title: 'Seamless Parent Linking',
      subtitle: 'Connect Families Instantly',
      description:
          'Generate unique codes for each student. Parents register and link instantly - no manual setup needed.',
      features: [
        'Unique student codes',
        'Instant parent verification',
        'Secure linking protocol',
        'Multiple parent support',
        'Easy unlinking options',
      ],
      icon: Icons.link,
      color: AppColors.softYellow,
    ),
    _DemoSlide(
      title: 'Key Benefits',
      subtitle: 'Why Schools Choose Lumi',
      description: '',
      features: [
        '📊 Real-time data & insights',
        '🎯 Increased reading engagement',
        '📱 Works offline everywhere',
        '🔒 Secure & GDPR compliant',
        '⚡ Quick 15-minute setup',
        '💬 Excellent support',
      ],
      icon: Icons.star,
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
                  const LumiMascot(
                    mood: LumiMood.happy,
                    size: 40,
                  ),
                  LumiGap.horizontalXS,
                  Text(
                    'Lumi Reading Diary',
                    style: LumiTextStyles.h2(color: AppColors.rosePink),
                  ),
                  const Spacer(),
                  LumiTextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DemoRequestScreen(),
                        ),
                      );
                    },
                    text: 'Skip to Registration',
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => Container(
                    margin: EdgeInsets.symmetric(horizontal: LumiSpacing.xxs),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.rosePink
                          : AppColors.charcoal.withValues(alpha: 0.2),
                      borderRadius: LumiBorders.small,
                    ),
                  ).animate().scale(
                        duration: 200.ms,
                      ),
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: LumiPadding.allM,
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
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_DemoSlide slide) {
    return SingleChildScrollView(
      padding: LumiPadding.allM,
      child: Column(
        children: [
          // Icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              slide.icon,
              size: 60,
              color: slide.color,
            ),
          ).animate().scale(delay: 200.ms, duration: 500.ms),

          LumiGap.l,

          // Title
          Text(
            slide.title,
            style: LumiTextStyles.displayMedium(color: AppColors.charcoal),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

          LumiGap.xs,

          // Subtitle
          Text(
            slide.subtitle,
            style: LumiTextStyles.h3(color: slide.color),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

          LumiGap.m,

          // Description
          if (slide.description.isNotEmpty)
            Text(
              slide.description,
              style: LumiTextStyles.bodyLarge(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

          LumiGap.l,

          // Features
          if (slide.features != null)
            ...slide.features!.asMap().entries.map((entry) {
              final index = entry.key;
              final feature = entry.value;
              return Container(
                margin: EdgeInsets.only(bottom: LumiSpacing.xs),
                padding: LumiPadding.allS,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: LumiBorders.medium,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.charcoal.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: slide.color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check,
                        color: slide.color,
                        size: 20,
                      ),
                    ),
                    LumiGap.horizontalS,
                    Expanded(
                      child: Text(
                        feature,
                        style: LumiTextStyles.bodyMedium(color: AppColors.charcoal),
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: (600 + (index * 100)).ms, duration: 500.ms)
                  .slideX(begin: 0.2, end: 0);
            }),
        ],
      ),
    );
  }
}

class _DemoSlide {
  final String title;
  final String subtitle;
  final String description;
  final List<String>? features;
  final IconData icon;
  final Color color;

  _DemoSlide({
    required this.title,
    required this.subtitle,
    required this.description,
    this.features,
    required this.icon,
    required this.color,
  });
}
