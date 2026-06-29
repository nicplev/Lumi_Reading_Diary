import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/blob_selector.dart';
import '../../core/widgets/lumi/comment_chips.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/school_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/parent_comment_settings.dart';
import '../../data/models/comprehension_recording_settings.dart';
import '../../data/providers/active_child_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_log_service.dart';
import '../../services/platform_config_service.dart';
import '../../services/logging_engagement_service.dart';
import 'widgets/comprehension_recording_step.dart';

/// Celebration screen shown after a reading log is successfully saved.
/// Displays confetti, night count, streak info, and badge notifications.
class ReadingSuccessScreen extends ConsumerStatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final ReadingLogModel readingLog;
  final Map<String, dynamic>? updatedStats;

  /// True when this log bridged a missed night via rest-day tolerance.
  final bool restDayApplied;

  const ReadingSuccessScreen({
    super.key,
    required this.student,
    required this.parent,
    required this.readingLog,
    this.updatedStats,
    this.restDayApplied = false,
  });

  @override
  ConsumerState<ReadingSuccessScreen> createState() =>
      _ReadingSuccessScreenState();
}

class _ReadingSuccessScreenState extends ConsumerState<ReadingSuccessScreen>
    with TickerProviderStateMixin {
  late final AnimationController _confettiController;
  Timer? _autoNavigateTimer;

  /// The next un-logged child from the reminder the parent tapped, if any.
  /// Captured once in [initState] (after dropping the child we just logged) so
  /// the screen nudges toward logging the next sibling instead of idling home.
  String? _nextReminderChildId;

  /// First name of [_nextReminderChildId], resolved live from the child list.
  /// Null if there's no next child or it's no longer linked.
  String? get _nextChildName {
    final id = _nextReminderChildId;
    if (id == null) return null;
    final children =
        ref.read(parentChildrenProvider).value ?? const <StudentModel>[];
    for (final c in children) {
      if (c.id == id) return c.firstName;
    }
    return null;
  }

  // ─── Rec 2: progressive disclosure of feeling + comment ──────────
  // For a one-tap quick log the feeling/comment were skipped; offer them
  // here as an optional, post-hoc prompt instead of gating the log on them.

  /// The log was created via the one-tap path (`metadata.quickLog == true`).
  bool get _isQuickLog => widget.readingLog.metadata?['quickLog'] == true;

  /// Show the optional feeling prompt only for a quick log with no feeling yet.
  bool get _showFollowUp =>
      _isQuickLog && widget.readingLog.childFeeling == null;

  /// Running total of detailed logs (loaded for non-quick logs only), used for
  /// gentle milestone recognition.
  int? _detailedLogCount;

  /// A milestone affirmation message, or null when this isn't a milestone.
  String? get _detailedMilestone {
    final count = _detailedLogCount;
    if (count == null || count <= 0 || count % 5 != 0) return null;
    return "You've shared $count reading notes — "
        "${widget.student.firstName}'s teacher can see how it's going.";
  }

  ReadingFeeling? _pickedFeeling;

  ParentCommentSettings? _commentSettings;
  bool _noteExpanded = false;
  List<String> _selectedComments = [];
  final TextEditingController _noteController = TextEditingController();
  bool _commentSaved = false;

  // Comprehension recording — the highest-value teacher data, offered here as
  // an optional add-on to a one-tap log (when the school enables it).
  ComprehensionRecordingSettings _comprehensionSettings =
      ComprehensionRecordingSettings.defaults();
  String _comprehensionQuestion = ClassModel.defaultComprehensionQuestion;
  ComprehensionRecordingResult? _comprehensionRecording;
  bool _comprehensionExpanded = false;
  bool _comprehensionSaved = false;

  bool get _comprehensionEnabled => _comprehensionSettings.enabled;

  int get _totalNights =>
      widget.updatedStats?['totalReadingDays'] ??
      widget.student.stats?.totalReadingDays ??
      0;

  int get _currentStreak =>
      widget.updatedStats?['currentStreak'] ??
      widget.student.stats?.currentStreak ??
      0;

  int get _last30Nights =>
      widget.updatedStats?['last30DaysCount'] ??
      widget.student.stats?.last30DaysCount ??
      0;

  // Cumulative-nights milestones, unified with the achievement ladder
  // (AchievementThresholds.readingDays) so the celebration matches the badge
  // the Cloud Function actually awards. 1 night = the "First Chapter" special.
  String? get _earnedBadge {
    if (_totalNights == 1) return 'First Night';
    for (final t in AchievementThresholds.defaults.readingDays) {
      if (_totalNights == t) return '$t Nights';
    }
    return null;
  }

  int get _nextMilestone {
    for (final t in AchievementThresholds.defaults.readingDays) {
      if (_totalNights < t) return t;
    }
    return ((_totalNights ~/ 100) + 1) * 100;
  }

  /// The threshold the child has already passed — the floor of the current
  /// band, so the progress bar fills within [prev, next] rather than from 0.
  int get _prevMilestone {
    int prev = 0;
    for (final t in AchievementThresholds.defaults.readingDays) {
      if (_totalNights >= t) prev = t;
    }
    return prev;
  }

  @override
  void initState() {
    super.initState();
    // Multi-child reminder: drop the child we just logged from the queue and
    // capture the next one (if any) so we can nudge toward it rather than
    // returning home and leaving a sibling silently un-logged.
    ref.read(pendingReminderChildIdsProvider.notifier).remove(widget.student.id);
    final remaining = ref.read(pendingReminderChildIdsProvider);
    _nextReminderChildId = remaining.isNotEmpty ? remaining.first : null;

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _logAnalytics();
    if (_showFollowUp) {
      // Quick log: offer the optional feeling / comment / comprehension prompt
      // and let the parent leave on their own terms — no rushed navigation.
      _loadFollowUpSettings();
    } else {
      // Detailed log: recognise the effort with an occasional affirmation, and
      // give a touch longer to read it before returning home.
      LoggingEngagementService.instance.detailedLogCount().then((value) {
        if (mounted) setState(() => _detailedLogCount = value);
      });
      // Only auto-return home when there's no next child to nudge toward —
      // otherwise the parent chooses when to move on.
      if (_nextReminderChildId == null) {
        _autoNavigateTimer = Timer(const Duration(seconds: 4), _goHome);
      }
    }
  }

  /// Loads the optional follow-up settings: parent-comment presets plus the
  /// comprehension toggle (school + platform kill switch) and per-class
  /// question — mirroring the full logging flow.
  Future<void> _loadFollowUpSettings() async {
    try {
      final firestore = FirebaseService.instance.firestore;
      final schoolId = widget.readingLog.schoolId;
      final schoolFuture =
          firestore.collection('schools').doc(schoolId).get();
      final classFuture = widget.student.classId.isNotEmpty
          ? firestore
              .collection('schools')
              .doc(schoolId)
              .collection('classes')
              .doc(widget.student.classId)
              .get()
          : Future<DocumentSnapshot<Map<String, dynamic>>?>.value(null);
      // Platform kill switch fetched alongside; never throws (fails open).
      final platformEnabledFuture =
          PlatformConfigService().isComprehensionRecordingEnabled();
      final results = await Future.wait([schoolFuture, classFuture]);
      final platformEnabled = await platformEnabledFuture;
      if (!mounted) return;
      final schoolDoc = results[0]!;
      final classDoc = results[1];
      setState(() {
        if (schoolDoc.exists) {
          final school = SchoolModel.fromFirestore(schoolDoc);
          _commentSettings = school.parentCommentSettings;
          _comprehensionSettings = ComprehensionRecordingSettings(
            enabled: platformEnabled &&
                school.comprehensionRecordingSettings.enabled,
          );
        }
        if (classDoc != null && classDoc.exists) {
          _comprehensionQuestion =
              ClassModel.fromFirestore(classDoc).comprehensionQuestion;
        }
      });
    } catch (_) {
      // Optional UI — safe to proceed with defaults.
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
          selections:
              _selectedComments.take(kMaxParentCommentChips).toList(),
          freeText: _noteController.text,
        );
        _commentSaved = true;
      } catch (_) {
        // Non-critical — proceed home regardless.
      }
    }

    final recording = _comprehensionRecording;
    if (recording != null && !_comprehensionSaved) {
      try {
        await ReadingLogService.instance.attachComprehension(
          widget.readingLog,
          localFilePath: recording.localPath,
          durationSec: recording.durationSec,
        );
        _comprehensionSaved = true;
      } catch (_) {
        // Non-critical — the recording is queued for retry on failure.
      }
    }
    _goHome();
  }

  void _goHome() {
    _autoNavigateTimer?.cancel();
    _autoNavigateTimer = null;
    if (!mounted) return;
    final nextId = _nextReminderChildId;
    if (nextId != null) {
      // Walk the parent to the next child from their reminder; the home screen's
      // tonight card surfaces it ready to log. A stale id (child since
      // unlinked) is harmless — activeChildProvider falls back to a valid child.
      ref.read(activeChildIdProvider.notifier).select(nextId);
    }
    context.go('/parent/home');
  }

  /// Stop the reminder walk-through early (detailed log already saved): clear
  /// the queue and go straight home.
  void _finishRemindersAndHome() {
    ref.read(pendingReminderChildIdsProvider.notifier).clear();
    _nextReminderChildId = null;
    _goHome();
  }

  /// Stop the walk-through from the quick-log follow-up: clear the queue, then
  /// save this child's optional note/recording before going home.
  void _bailFollowUp() {
    ref.read(pendingReminderChildIdsProvider.notifier).clear();
    _nextReminderChildId = null;
    _finishFollowUp();
  }

  /// CTA shown when the parent still has another child to log from the reminder
  /// they tapped — advances to that child rather than returning home.
  Widget _buildNextChildCta() {
    final name = _nextChildName;
    return Column(
      children: [
        Text(
          name != null
              ? 'Nice! $name still needs logging.'
              : 'Nice! One more to log.',
          style: LumiType.caption.copyWith(color: LumiTokens.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        LumiPrimaryButton(
          onPressed: _goHome,
          text: name != null ? 'Log $name next' : 'Log the next child',
          isFullWidth: true,
          icon: Icons.arrow_forward_rounded,
          color: LumiTokens.red,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _finishRemindersAndHome,
          child: Text('Done for now',
              style: LumiType.caption.copyWith(color: LumiTokens.muted)),
        ),
      ],
    );
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
    return LumiSectionScope(
      section: LumiSectionTheme.home,
      child: Scaffold(
        backgroundColor: LumiTokens.cream,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Stack(
            children: [
              // Confetti overlay
              _ConfettiOverlay(controller: _confettiController),

              // Main content
              Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Checkmark circle — green is the universal "confirmed".
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          color: LumiTokens.green,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: LumiTokens.green.withValues(alpha: 0.3),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.check_rounded,
                            color: LumiTokens.paper, size: 44),
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
                        style: LumiType.heading.copyWith(fontSize: 32),
                        textAlign: TextAlign.center,
                      ).animate().fadeIn(delay: 300.ms),

                      const SizedBox(height: 8),

                      // Night count
                      Text(
                        'Night $_totalNights complete',
                        style: LumiType.bodyL.copyWith(color: LumiTokens.muted),
                      ).animate().fadeIn(delay: 400.ms),

                      const SizedBox(height: 28),

                      // Streak — motivational only (streaks earn no badge), so
                      // it sits below the headline rather than dominating it.
                      if (_currentStreak > 0)
                        _StatPill(
                          icon: Icons.local_fire_department_rounded,
                          label: '$_currentStreak day streak',
                          color: LumiTokens.red,
                        ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.3),

                      // Shame-free framing — a missed night is absorbed by a
                      // rest day, so the streak simply keeps going.
                      if (widget.restDayApplied) ...[
                        const SizedBox(height: 10),
                        _StatPill(
                          icon: Icons.bedtime_rounded,
                          label: 'Rest day — your streak keeps going!',
                          color: LumiTokens.blue,
                        ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.3),
                      ],

                      // Forgiving rhythm: nights in the last 30 — a sliding
                      // count that never resets.
                      if (_last30Nights > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bedtime_outlined,
                                size: 15, color: LumiTokens.blue),
                            const SizedBox(width: 6),
                            Text('$_last30Nights of the last 30 nights',
                                style: LumiType.caption),
                          ],
                        ).animate().fadeIn(delay: 750.ms),
                      ],

                      const SizedBox(height: 16),

                      // Badge earned notification
                      if (_earnedBadge != null) ...[
                        _StatPill(
                          icon: Icons.emoji_events_rounded,
                          label: 'Badge earned: $_earnedBadge!',
                          color: LumiTokens.yellow,
                          filled: true,
                        )
                            .animate()
                            .fadeIn(delay: 800.ms)
                            .slideY(begin: 0.3)
                            .then()
                            .shake(hz: 2, duration: 500.ms),
                        const SizedBox(height: 16),
                      ],

                      // Progress to next milestone (nights-read ladder).
                      _MilestoneCard(
                        prev: _prevMilestone,
                        next: _nextMilestone,
                        total: _totalNights,
                        accent: LumiTokens.yellow,
                      ).animate().fadeIn(delay: 1000.ms),

                      const SizedBox(height: 32),

                      // Rec 2: for a quick log, offer the optional feeling /
                      // comment prompt instead of auto-navigating away.
                      if (_showFollowUp)
                        _buildFollowUp().animate().fadeIn(delay: 900.ms)
                      else ...[
                        // Gentle, occasional recognition for the richer flow.
                        if (_detailedMilestone != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: LumiTokens.tintGreen.withValues(alpha: 0.5),
                              borderRadius:
                                  BorderRadius.circular(LumiTokens.radiusMedium),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.favorite_rounded,
                                    size: 18, color: LumiTokens.green),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(_detailedMilestone!,
                                      style: LumiType.caption),
                                ),
                              ],
                            ),
                          ).animate().fadeIn(delay: 700.ms),
                          const SizedBox(height: 16),
                        ],
                        // From a multi-child reminder: nudge to the next child
                        // rather than auto-returning home. Otherwise show the
                        // usual auto-returning indicator (tappable to skip).
                        if (_nextReminderChildId != null)
                          _buildNextChildCta().animate().fadeIn(delay: 600.ms)
                        else
                          GestureDetector(
                            onTap: _goHome,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: LumiTokens.muted,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('Returning home…',
                                    style: LumiType.caption),
                              ],
                            ),
                          ).animate().fadeIn(delay: 1200.ms),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
        _bentoCard(
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
              color: LumiTokens.red,
            )
          else
            _bentoCard(
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
                      cursorColor: LumiTokens.ink,
                      decoration: InputDecoration(
                        hintText: 'Anything else to add? (optional)',
                        filled: true,
                        fillColor: LumiTokens.cream,
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          borderSide: const BorderSide(color: LumiTokens.rule),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          borderSide: const BorderSide(color: LumiTokens.rule),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(LumiTokens.radiusMedium),
                          borderSide:
                              const BorderSide(color: LumiTokens.red, width: 2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        // Comprehension question — same card as the logging flow: the teacher's
        // question is the hero, the child records an answer. Optional, collapsed
        // by default so the one-tap parent isn't slowed down.
        if (_comprehensionEnabled) ...[
          const SizedBox(height: 12),
          if (_comprehensionRecording == null && !_comprehensionExpanded)
            LumiTextButton(
              onPressed: () => setState(() => _comprehensionExpanded = true),
              text: 'Record ${widget.student.firstName} reading',
              icon: Icons.mic_none_rounded,
              color: LumiTokens.red,
            )
          else
            _bentoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.mic_none_rounded,
                          size: 18, color: LumiTokens.red),
                      const SizedBox(width: 8),
                      Text(
                        'Comprehension question',
                        style:
                            LumiType.body.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _comprehensionQuestion,
                    style: LumiType.bodyL.copyWith(
                      color: LumiTokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ask ${widget.student.firstName} to answer out loud — '
                    'optional.',
                    style: LumiType.caption.copyWith(color: LumiTokens.muted),
                  ),
                  const SizedBox(height: 16),
                  ComprehensionRecordingStep(
                    embedded: true,
                    question: _comprehensionQuestion,
                    logId: widget.readingLog.id,
                    initialLocalPath: _comprehensionRecording?.localPath,
                    initialDurationSec: _comprehensionRecording?.durationSec,
                    onRecordingChanged: (r) =>
                        setState(() => _comprehensionRecording = r),
                    onSkip: () => setState(() {
                      _comprehensionExpanded = false;
                      _comprehensionRecording = null;
                    }),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 20),
        // From a multi-child reminder, "Done" saves this child and advances to
        // the next; otherwise it just finishes and returns home.
        LumiPrimaryButton(
          onPressed: _finishFollowUp,
          text: _nextReminderChildId != null
              ? 'Log ${_nextChildName ?? 'the next child'} next'
              : 'Done',
          isFullWidth: true,
          icon: _nextReminderChildId != null
              ? Icons.arrow_forward_rounded
              : Icons.check,
          color: LumiTokens.red,
        ),
        if (_nextReminderChildId != null)
          TextButton(
            onPressed: _bailFollowUp,
            child: Text('Done for now',
                style: LumiType.caption.copyWith(color: LumiTokens.muted)),
          ),
      ],
    );
  }
}

/// Flat bento tile (paper surface, hairline rule border, no shadow) — the
/// success screen's card surface, matching the logging flow.
Widget _bentoCard({required Widget child, EdgeInsetsGeometry? padding}) {
  return Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: LumiTokens.paper,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      border: Border.all(color: LumiTokens.rule),
    ),
    child: child,
  );
}

/// A single rounded stat pill (streak / rest-day / badge). Soft tinted fill
/// with a coloured icon by default; [filled] uses a stronger tint for the
/// badge-earned moment.
class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: LumiType.subhead.copyWith(fontSize: 17),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// Progress within the current nights-read band [prev, next]. Fills from the
/// last threshold the child passed, so the bar reflects real distance to the
/// next badge rather than starting from zero each time.
class _MilestoneCard extends StatelessWidget {
  final int prev;
  final int next;
  final int total;
  final Color accent;

  const _MilestoneCard({
    required this.prev,
    required this.next,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final span = (next - prev).clamp(1, 1 << 30);
    final fraction = ((total - prev) / span).clamp(0.0, 1.0);
    final remaining = (next - total).clamp(0, 1 << 30);

    return _bentoCard(
      child: Column(
        children: [
          Text(
            '$remaining ${remaining == 1 ? 'night' : 'nights'} to your next badge',
            style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: LumiTokens.rule,
              valueColor: AlwaysStoppedAnimation(accent),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$prev', style: LumiType.caption),
              Text('$next', style: LumiType.caption),
            ],
          ),
        ],
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
        LumiTokens.red,
        LumiTokens.green,
        LumiTokens.yellow,
        LumiTokens.blue,
        LumiTokens.orange,
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
