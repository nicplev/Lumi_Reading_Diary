import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/analytics_service.dart';

/// Celebration screen shown after a reading log is successfully saved.
/// Displays confetti, night count, streak info, and badge notifications.
class ReadingSuccessScreen extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final ReadingLogModel readingLog;
  final Map<String, dynamic>? updatedStats;

  const ReadingSuccessScreen({
    super.key,
    required this.student,
    required this.parent,
    required this.readingLog,
    this.updatedStats,
  });

  @override
  State<ReadingSuccessScreen> createState() => _ReadingSuccessScreenState();
}

class _ReadingSuccessScreenState extends State<ReadingSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  Timer? _autoNavigateTimer;

  int get _totalNights =>
      widget.updatedStats?['totalReadingDays'] ??
      widget.student.stats?.totalReadingDays ??
      0;

  int get _currentStreak =>
      widget.updatedStats?['currentStreak'] ??
      widget.student.stats?.currentStreak ??
      0;

  // Check if a badge milestone was just reached
  String? get _earnedBadge {
    const milestones = {
      1: 'First Night',
      25: '25 Nights',
      50: '50 Nights',
      100: '100 Nights',
    };
    return milestones[_totalNights];
  }

  int get _nextMilestone {
    const milestones = [25, 50, 75, 100, 150, 200];
    for (final m in milestones) {
      if (_totalNights < m) return m;
    }
    return ((_totalNights ~/ 50) + 1) * 50;
  }

  @override
  void initState() {
    super.initState();
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _logAnalytics();
    _autoNavigateTimer = Timer(const Duration(seconds: 3), _goHome);
  }

  void _goHome() {
    _autoNavigateTimer?.cancel();
    _autoNavigateTimer = null;
    if (mounted) {
      context.go('/parent/home', extra: widget.parent);
    }
  }

  void _logAnalytics() {
    final log = widget.readingLog;
    AnalyticsService.instance.logReadingLogged(
      feeling: log.childFeeling?.name ?? 'none',
      bookCount: log.bookTitles.length,
      minutesRead: log.minutesRead,
    );

    if (_earnedBadge != null) {
      AnalyticsService.instance.logBadgeEarned(badgeType: _earnedBadge!);
    }

    // Log streak milestones at 7, 14, 30, 60, 100
    const streakMilestones = {7, 14, 30, 60, 100};
    if (streakMilestones.contains(_currentStreak)) {
      AnalyticsService.instance.logStreakMilestone(streakCount: _currentStreak);
    }
  }

  @override
  void dispose() {
    _autoNavigateTimer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Confetti overlay
            _ConfettiOverlay(controller: _confettiController),

            // Main content
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Checkmark circle
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppColors.white,
                        size: 40,
                      ),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0, 0),
                          end: const Offset(1, 1),
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                        )
                        .fadeIn(duration: 300.ms),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      'Reading Logged!',
                      style: LumiTextStyles.h1(color: AppColors.charcoal),
                    ).animate().fadeIn(delay: 300.ms),

                    const SizedBox(height: 12),

                    // Night count
                    Text(
                      'Night $_totalNights complete',
                      style: LumiTextStyles.bodyLarge(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ).animate().fadeIn(delay: 400.ms),

                    const SizedBox(height: 32),

                    // Streak badge
                    if (_currentStreak > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.rosePink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.rosePink.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department, color: AppColors.rosePink, size: 28),
                            const SizedBox(width: 8),
                            Text(
                              '$_currentStreak Day Streak',
                              style: LumiTextStyles.h3(color: AppColors.rosePink),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.3),

                    const SizedBox(height: 16),

                    // Badge earned notification
                    if (_earnedBadge != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softYellow.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: AppColors.softYellow,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 24)),
                            const SizedBox(width: 8),
                            Text(
                              'Badge Earned: $_earnedBadge!',
                              style: LumiTextStyles.h3(color: AppColors.charcoal),
                            ),
                          ],
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 800.ms)
                          .slideY(begin: 0.3)
                          .then()
                          .shake(hz: 2, duration: 500.ms),
                      const SizedBox(height: 16),
                    ],

                    // Progress to next milestone
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.offWhite,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_nextMilestone - _totalNights} nights to next badge',
                            style: LumiTextStyles.bodySmall(
                              color: AppColors.charcoal.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _totalNights / _nextMilestone,
                              backgroundColor:
                                  AppColors.charcoal.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                AppColors.rosePink,
                              ),
                              minHeight: 8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '$_totalNights',
                                style: LumiTextStyles.caption(),
                              ),
                              Text(
                                '$_nextMilestone',
                                style: LumiTextStyles.caption(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 1000.ms),

                    const SizedBox(height: 40),

                    // Auto-returning indicator (tappable to skip)
                    GestureDetector(
                      onTap: _goHome,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.charcoal.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Returning home...',
                            style: LumiTextStyles.bodySmall(
                              color: AppColors.charcoal.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 1200.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple confetti animation using custom painting.
class _ConfettiOverlay extends StatelessWidget {
  final AnimationController controller;

  const _ConfettiOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _ConfettiPainter(progress: controller.value),
          size: MediaQuery.of(context).size,
        );
      },
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final Random _random = Random(42);
  static final List<_ConfettiParticle> _particles = List.generate(
    40,
    (_) => _ConfettiParticle(
      x: _random.nextDouble(),
      speed: 0.3 + _random.nextDouble() * 0.7,
      size: 4 + _random.nextDouble() * 6,
      color: [
        AppColors.rosePink,
        AppColors.mintGreen,
        AppColors.softYellow,
        AppColors.skyBlue,
        AppColors.warmOrange,
      ][_random.nextInt(5)],
      wobble: _random.nextDouble() * 2 * pi,
    ),
  );

  _ConfettiPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1.0) return;

    for (final particle in _particles) {
      final opacity = (1.0 - progress).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = particle.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      final x = particle.x * size.width +
          sin(progress * 4 + particle.wobble) * 20;
      final y = progress * size.height * particle.speed;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: particle.size,
            height: particle.size * 0.6,
          ),
          Radius.circular(particle.size * 0.2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _ConfettiParticle {
  final double x;
  final double speed;
  final double size;
  final Color color;
  final double wobble;

  const _ConfettiParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.color,
    required this.wobble,
  });
}
