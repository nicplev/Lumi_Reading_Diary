import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../auth/login_screen.dart';
import '../onboarding/demo_request_screen.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          children: [
            _buildHeader(context),
            _buildHeroSection(context),
            _buildFeaturesSection(context),
            _buildHowItWorksSection(context),
            _buildBenefitsSection(context),
            _buildCallToActionSection(context),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6B8EF9), Color(0xFF9B7EF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B8EF9).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Lumi',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  foreground: Paint()
                    ..shader = const LinearGradient(
                      colors: [Color(0xFF6B8EF9), Color(0xFF9B7EF8)],
                    ).createShader(const Rect.fromLTWH(0, 0, 200, 70)),
                ),
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 600.ms)
              .slideX(begin: -0.2, end: 0, curve: Curves.easeOut),

          // Navigation buttons
          Row(
            children: [
              LumiTextButton(
                text: 'Login',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                },
              ),
              const SizedBox(width: 12),
              LumiPrimaryButton(
                text: 'Request Demo',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DemoRequestScreen()),
                  );
                },
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 600.ms, delay: 200.ms)
              .slideX(begin: 0.2, end: 0, curve: Curves.easeOut),
        ],
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Column(
        children: [
          // Main headline
          Text(
            'Transform Reading into\nMagical Adventures',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              height: 1.2,
              color: AppColors.charcoal,
            ),
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 300.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),

          const SizedBox(height: 24),

          // Subheadline
          Text(
            'The digital reading diary that makes tracking student progress simple,\nengaging, and fun for teachers, parents, and students.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              color: AppColors.charcoal.withValues(alpha: 0.7),
              height: 1.6,
            ),
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 500.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),

          const SizedBox(height: 48),

          // CTA Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LumiPrimaryButton(
                text: 'Start Free Trial',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DemoRequestScreen()),
                  );
                },
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(width: 20),
              LumiSecondaryButton(
                text: 'See How It Works',
                onPressed: () {
                  // Scroll to how it works section
                  _scrollController.animateTo(
                    800,
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeInOut,
                  );
                },
                icon: Icons.play_circle_outline_rounded,
              ),
            ],
          )
              .animate()
              .fadeIn(duration: 800.ms, delay: 700.ms)
              .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),

          const SizedBox(height: 80),

          // Hero illustration
          Container(
            constraints: const BoxConstraints(maxWidth: 900),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B8EF9).withValues(alpha: 0.2),
                  blurRadius: 60,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Container(
                height: 500,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF6B8EF9).withValues(alpha: 0.1),
                      const Color(0xFF9B7EF8).withValues(alpha: 0.1),
                      const Color(0xFFFF8C42).withValues(alpha: 0.1),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // Placeholder for app screenshot or illustration
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            size: 120,
                            color:
                                const Color(0xFF6B8EF9).withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '📚 Dashboard Preview',
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B8EF9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Floating elements
                    Positioned(
                      top: 40,
                      right: 40,
                      child: _buildFloatingCard(
                        '🎯',
                        'Track Progress',
                        const Color(0xFF6B8EF9),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .moveY(begin: 0, end: -10, duration: 2.seconds)
                          .then()
                          .moveY(begin: -10, end: 0, duration: 2.seconds),
                    ),
                    Positioned(
                      bottom: 60,
                      left: 40,
                      child: _buildFloatingCard(
                        '⭐',
                        '20 mins read',
                        const Color(0xFFFF8C42),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .moveY(
                              begin: 0,
                              end: -15,
                              duration: 2.5.seconds,
                              delay: 500.ms)
                          .then()
                          .moveY(begin: -15, end: 0, duration: 2.5.seconds),
                    ),
                    Positioned(
                      top: 120,
                      left: 60,
                      child: _buildFloatingCard(
                        '📖',
                        'New Book',
                        const Color(0xFF9B7EF8),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .moveY(
                              begin: 0,
                              end: -12,
                              duration: 2.2.seconds,
                              delay: 1.seconds)
                          .then()
                          .moveY(begin: -12, end: 0, duration: 2.2.seconds),
                    ),
                  ],
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(duration: 1000.ms, delay: 900.ms)
              .slideY(begin: 0.2, end: 0, curve: Curves.easeOut)
              .scale(
                  begin: const Offset(0.9, 0.9), end: const Offset(1.0, 1.0)),
        ],
      ),
    );
  }

  Widget _buildFloatingCard(String emoji, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      color: AppColors.white,
      child: Column(
        children: [
          Text(
            'Everything You Need in One Place',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Powerful features designed for teachers, parents, and school administrators',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 64),
          Wrap(
            spacing: 32,
            runSpacing: 32,
            alignment: WrapAlignment.center,
            children: [
              _buildFeatureCard(
                icon: Icons.dashboard_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6B8EF9), Color(0xFF9B7EF8)],
                ),
                title: 'Teacher Dashboard',
                description:
                    'Real-time insights into student reading progress with beautiful visualizations and analytics',
              ),
              _buildFeatureCard(
                icon: Icons.family_restroom_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF8C42), Color(0xFFFFB366)],
                ),
                title: 'Parent App',
                description:
                    'Simple one-tap logging, streak tracking, and progress history for busy families',
              ),
              _buildFeatureCard(
                icon: Icons.school_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF9B7EF8), Color(0xFFB89EF8)],
                ),
                title: 'Admin Control',
                description:
                    'Manage your entire school with user management, class setup, and custom reading levels',
              ),
              _buildFeatureCard(
                icon: Icons.assignment_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFF4ECDC4), Color(0xFF6FE7DB)],
                ),
                title: 'Smart Allocations',
                description:
                    'Assign reading by level, title, or free choice with flexible schedules that work for you',
              ),
              _buildFeatureCard(
                icon: Icons.cloud_sync_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B9D), Color(0xFFFF8BB5)],
                ),
                title: 'Offline Support',
                description:
                    'Log readings without internet and auto-sync when connected for uninterrupted tracking',
              ),
              _buildFeatureCard(
                icon: Icons.notifications_active_rounded,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFC837), Color(0xFFFFD666)],
                ),
                title: 'Smart Reminders',
                description:
                    'Gentle push notifications to keep reading streaks alive without overwhelming families',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Gradient gradient,
    required String title,
    required String description,
  }) {
    return SizedBox(
      width: 340,
      child: LumiCard(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: gradient.colors.first.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                description,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildHowItWorksSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      constraints: const BoxConstraints(maxWidth: 1200),
      child: Column(
        children: [
          Text(
            'How Lumi Works',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Three simple steps to transform reading at your school',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 64),
          _buildHowItWorksStep(
            number: '1',
            title: 'Schools Set Up',
            description:
                'Admins create classes, add teachers, and configure reading levels in minutes',
            emoji: '🏫',
            color: const Color(0xFF6B8EF9),
          ),
          const SizedBox(height: 32),
          _buildHowItWorksStep(
            number: '2',
            title: 'Teachers Assign',
            description:
                'Teachers create smart reading allocations tailored to each student\'s level',
            emoji: '📚',
            color: const Color(0xFF9B7EF8),
          ),
          const SizedBox(height: 32),
          _buildHowItWorksStep(
            number: '3',
            title: 'Parents Track',
            description:
                'Parents log daily reading with one tap and watch their child\'s progress soar',
            emoji: '⭐',
            color: const Color(0xFFFF8C42),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep({
    required String number,
    required String title,
    required String description,
    required String emoji,
    required Color color,
  }) {
    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.7)],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  number,
                  style: GoogleFonts.poppins(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideX(begin: -0.1, end: 0);
  }

  Widget _buildBenefitsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      color: AppColors.white,
      child: Column(
        children: [
          Text(
            'Why Schools Love Lumi',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 64),
          Wrap(
            spacing: 48,
            runSpacing: 48,
            alignment: WrapAlignment.center,
            children: [
              _buildBenefitItem(
                emoji: '⚡',
                title: 'Save Time',
                description:
                    'Reduce admin work by 80% with automated tracking and parent linking',
              ),
              _buildBenefitItem(
                emoji: '📈',
                title: 'Boost Engagement',
                description:
                    'Students read 3x more with gamification and family involvement',
              ),
              _buildBenefitItem(
                emoji: '💡',
                title: 'Data-Driven',
                description:
                    'Make informed decisions with real-time analytics and insights',
              ),
              _buildBenefitItem(
                emoji: '🔒',
                title: 'Secure & Private',
                description:
                    'Bank-level encryption with GDPR and COPPA compliance',
              ),
              _buildBenefitItem(
                emoji: '🌟',
                title: 'Easy Setup',
                description:
                    'Get started in under 10 minutes with our guided onboarding',
              ),
              _buildBenefitItem(
                emoji: '💚',
                title: 'Family Friendly',
                description:
                    'Parents love the simple interface and instant progress updates',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem({
    required String emoji,
    required String title,
    required String description,
  }) {
    return SizedBox(
      width: 300,
      child: Column(
        children: [
          Text(
            emoji,
            style: const TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.charcoal.withValues(alpha: 0.7),
              height: 1.6,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.0, 1.0));
  }

  Widget _buildCallToActionSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 80),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6B8EF9),
            Color(0xFF9B7EF8),
            Color(0xFFFF8C42),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6B8EF9).withValues(alpha: 0.4),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Ready to Transform Reading at Your School?',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 42,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Join hundreds of schools using Lumi to inspire a love of reading',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 20,
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LumiPrimaryButton(
                text: 'Start Your Free Trial',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const DemoRequestScreen()),
                  );
                },
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(width: 24),
              LumiSecondaryButton(
                text: 'Login',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTrustBadge(
                  Icons.check_circle_rounded, 'No credit card required'),
              const SizedBox(width: 32),
              _buildTrustBadge(Icons.timer_rounded, 'Setup in 10 minutes'),
              const SizedBox(width: 32),
              _buildTrustBadge(
                  Icons.support_agent_rounded, 'Free onboarding support'),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.2, end: 0);
  }

  Widget _buildTrustBadge(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      color: AppColors.charcoal,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo and tagline
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6B8EF9), Color(0xFF9B7EF8)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: AppColors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Lumi',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Making reading magical for every child',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),

              // Quick links
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Links',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFooterLink('Request Demo', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const DemoRequestScreen()),
                    );
                  }),
                  _buildFooterLink('Login', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LoginScreen()),
                    );
                  }),
                ],
              ),
            ],
          ),
          const SizedBox(height: 48),
          Divider(color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          Text(
            '© 2025 Lumi Reading Diary. All rights reserved.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String text, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.8),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
