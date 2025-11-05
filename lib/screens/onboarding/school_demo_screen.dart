import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
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
      color: AppColors.primaryBlue,
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
      color: AppColors.success,
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
      color: AppColors.secondaryPurple,
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
      color: AppColors.warning,
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
      color: AppColors.info,
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
      color: AppColors.primaryBlue,
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
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const LumiMascot(
                    mood: LumiMood.happy,
                    size: 40,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Lumi Reading Diary',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryBlue,
                        ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DemoRequestScreen(),
                        ),
                      );
                    },
                    child: const Text('Skip to Registration'),
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
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.primaryBlue
                          : AppColors.lightGray,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ).animate().scale(
                        duration: 200.ms,
                      ),
                ),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _previousPage,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                        child: const Text('Previous'),
                      ),
                    ),
                  if (_currentPage > 0) const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'Get Started'
                            : 'Next',
                      ),
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
      padding: const EdgeInsets.all(24),
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

          const SizedBox(height: 32),

          // Title
          Text(
            slide.title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGray,
                ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 300.ms, duration: 500.ms),

          const SizedBox(height: 12),

          // Subtitle
          Text(
            slide.subtitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: slide.color,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 400.ms, duration: 500.ms),

          const SizedBox(height: 24),

          // Description
          if (slide.description.isNotEmpty)
            Text(
              slide.description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.gray,
                    height: 1.5,
                  ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 500.ms, duration: 500.ms),

          const SizedBox(height: 32),

          // Features
          if (slide.features != null)
            ...slide.features!.asMap().entries.map((entry) {
              final index = entry.key;
              final feature = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        feature,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppColors.darkGray,
                                  fontWeight: FontWeight.w500,
                                ),
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
