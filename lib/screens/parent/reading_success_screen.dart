import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/blob_selector.dart';
import '../../core/widgets/lumi/comment_chips.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/school_model.dart';
import '../../data/models/parent_comment_settings.dart';
import '../../services/analytics_service.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_log_service.dart';

/// Celebration screen shown after a reading log is successfully saved.
/// Displays confetti, night count, streak info, and badge notifications.
class ReadingSuccessScreen extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final ReadingLogModel readingLog;
  final Map<String, dynamic>? updatedStats;

  /// True when this log spent a streak freeze to bridge a missed day.
  final bool freezeUsed;

  const ReadingSuccessScreen({
    super.key,
    required this.student,
    required this.parent,
    required this.readingLog,
    this.updatedStats,
    this.freezeUsed = false,
  });

  @override
  State<ReadingSuccessScreen> createState() => _ReadingSuccessScreenState();
}

class _ReadingSuccessScreenState extends State<ReadingSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  Timer? _autoNavigateTimer;

  // ─── Rec 2: progressive disclosure of feeling + comment ──────────
  // For a one-tap quick log the feeling/comment were skipped; offer them
  // here as an optional, post-hoc prompt instead of gating the log on them.

  /// The log was created via the one-tap path (`metadata.quickLog == true`).
  bool get _isQuickLog => widget.readingLog.metadata?['quickLog'] == true;

  /// Show the optional feeling prompt only for a quick log with no feeling yet.
  bool get _showFollowUp =>
      _isQuickLog && widget.readingLog.childFeeling == null;

  ReadingFeeling? _pickedFeeling;

  ParentCommentSettings? _commentSettings;
  bool _noteExpanded = false;
  List<String> _selectedComments = [];
  final TextEditingController _noteController = TextEditingController();
  bool _commentSaved = false;

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
    if (_showFollowUp) {
      // Quick log: offer the optional feeling/comment prompt and let the
      // parent leave on their own terms — no rushed auto-navigation.
      _loadCommentSettings();
    } else {
      _autoNavigateTimer = Timer(const Duration(seconds: 3), _goHome);
    }
  }

  Future<void> _loadCommentSettings() async {
    try {
      final doc = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.readingLog.schoolId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _commentSettings =
              SchoolModel.fromFirestore(doc).parentCommentSettings;
        });
      }
    } catch (_) {
      // Optional UI — safe to proceed without comment settings.
    }
  }

  /// Patches the chosen feeling onto the already-saved log.
  Future<void> _onFeelingSelected(ReadingFeeling feeling) async {
    setState(() => _pickedFeeling = feeling);
    try {
      await ReadingLogService.instance
          .attachFeeling(widget.readingLog, feeling);
    } catch (_) {
      // Feeling is optional — a failed patch is non-critical.
    }
  }

  /// Patches any note the parent added, then returns home.
  Future<void> _finishFollowUp() async {
    final hasNote = _noteExpanded &&
        (_selectedComments.isNotEmpty ||
            _noteController.text.trim().isNotEmpty);
    if (hasNote && !_commentSaved) {
      try {
        await ReadingLogService.instance.attachComment(
          widget.readingLog,
          selections: _selectedComments,
          freeText: _noteController.text,
        );
        _commentSaved = true;
      } catch (_) {
        // Non-critical — proceed home regardless.
      }
    }
    _goHome();
  }

  void _goHome() {
    _autoNavigateTimer?.cancel();
    _autoNavigateTimer = null;
    if (mounted) {
      context.go('/parent/home');
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
    _noteController.dispose();
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

                    // Rec 6: shame-free framing — celebrate the freeze that
                    // protected the streak rather than mourning a missed day.
                    if (widget.freezeUsed) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.skyBlue),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('❄️', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Freeze used — streak protected!',
                                style: LumiTextStyles.bodyMedium(
                                  color: AppColors.charcoal,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.3),
                    ],

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

                    const SizedBox(height: 32),

                    // Rec 2: for a quick log, offer the optional feeling /
                    // comment prompt instead of auto-navigating away.
                    if (_showFollowUp)
                      _buildFollowUp().animate().fadeIn(delay: 900.ms)
                    else
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
                                color:
                                    AppColors.charcoal.withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Returning home...',
                              style: LumiTextStyles.bodySmall(
                                color:
                                    AppColors.charcoal.withValues(alpha: 0.5),
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

  /// Optional post-log prompt shown for one-tap quick logs (Rec 2):
  /// a feeling selector and, if the school enables it, a note.
  Widget _buildFollowUp() {
    final settings = _commentSettings;
    final commentsEnabled = settings?.enabled ?? false;

    return Column(
      children: [
        // Feeling prompt — BlobSelector carries its own heading + helper text.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: AppColors.offWhite,
            borderRadius: BorderRadius.circular(20),
          ),
          child: BlobSelector(
            selectedFeeling: _pickedFeeling,
            onFeelingSelected: _onFeelingSelected,
          ),
        ),
        if (commentsEnabled) ...[
          const SizedBox(height: 12),
          if (!_noteExpanded)
            LumiTextButton(
              onPressed: () => setState(() => _noteExpanded = true),
              text: 'Add a note',
              icon: Icons.edit_note,
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.offWhite,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CommentChips(
                    selectedComments: _selectedComments,
                    onCommentsChanged: (comments) =>
                        setState(() => _selectedComments = comments),
                    categories: settings!.effectivePresets.isNotEmpty
                        ? settings.effectivePresets
                        : null,
                  ),
                  if (settings.freeTextEnabled) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText: 'Anything else to add? (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        const SizedBox(height: 20),
        LumiPrimaryButton(
          onPressed: _finishFollowUp,
          text: 'Done',
          isFullWidth: true,
          icon: Icons.check,
        ),
      ],
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
