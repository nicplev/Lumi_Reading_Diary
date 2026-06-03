import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/stats_card.dart';
import '../../core/widgets/lumi/week_progress_bar.dart';
import '../../core/widgets/lumi/progress_ring.dart';
import '../../core/widgets/lumi/lumi_book_card.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/services/navigation_state_service.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/providers/active_child_provider.dart';
import '../../services/book_cover_cache_service.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/reading_log_service.dart';
import '../../services/widget_data_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/staff_notification_service.dart';
import 'reading_history_screen.dart';
import 'parent_profile_screen.dart';
import 'widgets/parent_child_switcher.dart';

class ParentHomeScreen extends ConsumerStatefulWidget {
  final UserModel user;

  const ParentHomeScreen({
    super.key,
    required this.user,
  });

  @override
  ConsumerState<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends ConsumerState<ParentHomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  void _onCoversUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BookCoverCacheService.instance.addListener(_onCoversUpdated);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BookCoverCacheService.instance.removeListener(_onCoversUpdated);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Rec 4: reconcile any reading logged from the iOS widget while the app
    // was backgrounded.
    if (state == AppLifecycleState.resumed) {
      final children = ref.read(parentChildrenProvider).value;
      if (children != null && children.isNotEmpty) {
        WidgetDataService.instance.drainPendingWidgetLogs(
          children: children,
          parent: widget.user,
        );
        // Rec 3: if the active child has already been logged today, drop
        // today's scheduled reminder. Fire-and-forget — no need to await.
        final active = ref.read(activeChildProvider).value ?? children.first;
        if (active.stats?.lastReadingDate != null) {
          final last = active.stats!.lastReadingDate!;
          final now = DateTime.now();
          if (last.year == now.year &&
              last.month == now.month &&
              last.day == now.day) {
            NotificationService.instance
                .refreshReminderForToday(studentId: active.id);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the iOS/Android home-screen widget in sync with the child list.
    ref.listen<AsyncValue<List<StudentModel>>>(
      parentChildrenProvider,
      (_, next) {
        final children = next.value;
        if (children != null && children.isNotEmpty) {
          WidgetDataService.instance.updateFromChildren(
            children: children,
            selectedChildId:
                ref.read(activeChildProvider).value?.id ?? children.first.id,
            todaysLogs: const {},
            // Caches the parent so the lifecycle-driven drain can run on
            // resume from any parent screen (not only ParentHome).
            parent: widget.user,
          );
          // Rec 4: reconcile any reading logged from the iOS widget while
          // the app was closed.
          WidgetDataService.instance.drainPendingWidgetLogs(
            children: children,
            parent: widget.user,
          );
        }
      },
    );
    // Push the new selected child to the iOS widget when the parent switches
    // children via ParentChildSwitcher. Widgets configured as "Active child in
    // app" pick this up; widgets pinned to a specific child via the iOS
    // configuration intent ignore it.
    ref.listen<String?>(
      activeChildIdProvider,
      (_, __) {
        final children = ref.read(parentChildrenProvider).value;
        if (children == null || children.isEmpty) return;
        WidgetDataService.instance.updateFromChildren(
          children: children,
          selectedChildId:
              ref.read(activeChildProvider).value?.id ?? children.first.id,
          todaysLogs: const {},
          parent: widget.user,
        );
      },
    );

    return ref.watch(parentChildrenProvider).when(
          loading: () => const Scaffold(
            backgroundColor: AppColors.offWhite,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.rosePink),
            ),
          ),
          error: (_, __) => Scaffold(
            backgroundColor: AppColors.offWhite,
            body: _buildErrorView(),
          ),
          data: (children) {
            if (children.isEmpty) {
              return Scaffold(
                backgroundColor: AppColors.offWhite,
                body: _buildNoChildrenView(),
              );
            }
            final activeChild =
                ref.watch(activeChildProvider).value ?? children.first;
            return Scaffold(
              backgroundColor: AppColors.offWhite,
              body: IndexedStack(
                index: _selectedIndex,
                children: [
                  _buildHomeView(activeChild, children),
                  ReadingHistoryScreen(
                    // Re-key on the active child so a switch rebuilds the
                    // Bookshelf with fresh state instead of stale data.
                    key: ValueKey(activeChild.id),
                    studentId: activeChild.id,
                    parentId: widget.user.id,
                    schoolId: widget.user.schoolId!,
                  ),
                  ParentProfileScreen(user: widget.user),
                ],
              ),
              bottomNavigationBar: _buildBottomNav(),
            );
          },
        );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.rosePink,
          unselectedItemColor: AppColors.textSecondary,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: LumiTextStyles.caption(color: AppColors.rosePink)
              .copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: LumiTextStyles.caption(),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories_outlined),
              activeIcon: Icon(Icons.auto_stories),
              label: 'Bookshelf',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return SafeArea(
      child: Padding(
        padding: LumiPadding.allM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 56,
              color: AppColors.textSecondary,
            ),
            LumiGap.s,
            Text(
              'Couldn\'t load your children',
              style: LumiTextStyles.h3(color: AppColors.charcoal),
              textAlign: TextAlign.center,
            ),
            LumiGap.xs,
            Text(
              'Please check your connection and try again.',
              style: LumiTextStyles.bodyLarge(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            LumiGap.m,
            LumiPrimaryButton(
              onPressed: () => ref.invalidate(parentChildrenProvider),
              text: 'Retry',
              icon: Icons.refresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeView(
    StudentModel selectedChild,
    List<StudentModel> children,
  ) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // App Bar with child selector
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${widget.user.fullName.isNotEmpty ? widget.user.fullName.split(' ').first : 'Parent'}!',
                  style: LumiTextStyles.h3(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  selectedChild.firstName,
                  style: LumiTextStyles.h2(color: AppColors.charcoal),
                ),
              ],
            ),
            actions: [
              StreamBuilder<int>(
                stream: StaffNotificationService.instance
                    .watchUnreadParentNotificationCount(widget.user),
                builder: (context, snapshot) {
                  final unreadCount = snapshot.data ?? 0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Semantics(
                        label: unreadCount > 0
                            ? 'Notifications, $unreadCount unread'
                            : 'Notifications',
                        button: true,
                        child: LumiIconButton(
                          icon: Icons.notifications_outlined,
                          onPressed: () {
                            context.push('/parent/notifications');
                          },
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.rosePink,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: LumiTextStyles.caption(
                                color: AppColors.white,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),

          // Persistent child switcher — renders only for 2+ children.
          const SliverToBoxAdapter(child: ParentChildSwitcher()),

          // Content
          SliverPadding(
            padding: LumiPadding.allS,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Rec 5b: one Today card per child so a multi-child parent
                // can log every child without switching context. Each card
                // owns its own log + allocation streams (see _ChildTodayCard).
                if (children.length == 1)
                  _ChildTodayCard(
                    student: children.first,
                    parent: widget.user,
                  ).animate().fadeIn().scale()
                else
                  for (final child in children) ...[
                    _ChildTodayCard(
                      student: child,
                      parent: widget.user,
                      showChildName: true,
                    ).animate().fadeIn(),
                    LumiGap.s,
                  ],

                LumiGap.m,

                // Progress Ring + Weekly Progress
                _ProgressAndWeekSection(
                  studentId: selectedChild.id,
                  schoolId: widget.user.schoolId!,
                ).animate().fadeIn(delay: 100.ms),

                LumiGap.m,

                // Reading Stats
                StreamBuilder<StudentStats?>(
                  stream: _getStudentStats(selectedChild.id),
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    return StatsCard(
                      currentStreak: stats?.currentStreak ?? 0,
                      bestStreak: stats?.longestStreak ?? 0,
                      totalNights: stats?.totalReadingDays ?? 0,
                      streakFreezes: stats?.streakFreezesAvailable,
                    ).animate().fadeIn(delay: 300.ms);
                  },
                ),

                // Achievement near-miss nudge
                _AchievementNearMissCard(
                  studentId: selectedChild.id,
                  schoolId: widget.user.schoolId!,
                ).animate().fadeIn(delay: 400.ms),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoChildrenView() {
    return SafeArea(
      child: Padding(
        padding: LumiPadding.allM,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LumiMascot(
              variant: LumiVariant.parent,
              size: 150,
            ),
            LumiGap.m,
            Text(
              'No Children Linked',
              style: LumiTextStyles.h2(color: AppColors.charcoal),
            ),
            LumiGap.xs,
            Text(
              'Please ask your teacher for an invite code to link your children.',
              style: LumiTextStyles.bodyLarge(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            LumiGap.l,
            LumiPrimaryButton(
              onPressed: () => context.push('/parent/link-child'),
              text: 'Enter Invite Code',
              icon: Icons.qr_code,
            ),
          ],
        ),
      ),
    );
  }

  Stream<StudentStats?> _getStudentStats(String studentId) {
    final firebaseService = ref.read(firebaseServiceProvider);
    return firebaseService.firestore
        .collection('schools')
        .doc(widget.user.schoolId!)
        .collection('students')
        .doc(studentId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        final student = StudentModel.fromFirestore(doc);
        return student.stats;
      }
      return null;
    });
  }
}

/// Near-miss achievement nudge card.
/// Shown only when the student is ≥80% toward their next unearned achievement.
/// Hidden entirely when no near-miss exists.
class _AchievementNearMissCard extends StatefulWidget {
  final String studentId;
  final String schoolId;

  const _AchievementNearMissCard({
    required this.studentId,
    required this.schoolId,
  });

  @override
  State<_AchievementNearMissCard> createState() => _AchievementNearMissCardState();
}

class _AchievementNearMissCardState extends State<_AchievementNearMissCard> {
  AchievementThresholds _thresholds = AchievementThresholds.defaults;
  AchievementCustomization _customization = AchievementCustomization.empty;

  @override
  void initState() {
    super.initState();
    _loadThresholds();
  }

  Future<void> _loadThresholds() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .get();
      final settings = doc.data()?['settings'] as Map<String, dynamic>?;
      final rawThresholds    = settings?['achievementThresholds']    as Map<String, dynamic>?;
      final rawCustomization = settings?['achievementCustomization'] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          if (rawThresholds    != null) _thresholds    = AchievementThresholds.fromMap(rawThresholds);
          if (rawCustomization != null) _customization = AchievementCustomization.fromMap(rawCustomization);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('students')
          .doc(widget.studentId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) return const SizedBox.shrink();

        final student = StudentModel.fromFirestore(snapshot.data!);
        final stats = student.stats;
        if (stats == null) return const SizedBox.shrink();

        final earnedIds = (data['achievements'] as List<dynamic>? ?? [])
            .map((a) => a['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        // Rec 7: prefer a consistency-based near-miss (streak / days); fall
        // back to volume-based (books / minutes) only when none is close.
        final result = AchievementTemplates.nearestUnearned(
              currentStreak: stats.currentStreak,
              totalBooksRead: stats.totalBooksRead,
              totalMinutesRead: stats.totalMinutesRead,
              totalReadingDays: stats.totalReadingDays,
              earnedAchievementIds: earnedIds,
              thresholds: _thresholds,
              customization: _customization,
              minProgress: 0.8,
              requirementTypes: const {'streak', 'days'},
            ) ??
            AchievementTemplates.nearestUnearned(
              currentStreak: stats.currentStreak,
              totalBooksRead: stats.totalBooksRead,
              totalMinutesRead: stats.totalMinutesRead,
              totalReadingDays: stats.totalReadingDays,
              earnedAchievementIds: earnedIds,
              thresholds: _thresholds,
              customization: _customization,
              minProgress: 0.8,
            );

        if (result == null) return const SizedBox.shrink();

        final achievement = result.achievement;
        final progress = result.progress;
        final rarityColor = Color(achievement.effectiveColor);

        int current;
        int remaining;
        String unit;
        switch (achievement.requirementType) {
          case 'streak':
            current = stats.currentStreak;
            break;
          case 'books':
            current = stats.totalBooksRead;
            break;
          case 'minutes':
            current = stats.totalMinutesRead;
            break;
          case 'days':
          default:
            current = stats.totalReadingDays;
            break;
        }
        remaining = achievement.requiredValue - current;
        unit = remaining == 1
            ? achievement.requirementType == 'books' ? 'book' : 'day'
            : achievement.requirementType == 'books' ? 'books' : 'days';

        return GestureDetector(
          onTap: () => context.push(
            '/parent/achievements',
            extra: {'student': student},
          ),
          child: Container(
            margin: EdgeInsets.only(top: LumiSpacing.m),
            padding: LumiPadding.allM,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  rarityColor.withValues(alpha: 0.08),
                  AppColors.white,
                ],
              ),
              borderRadius: LumiBorders.large,
              border: Border.all(
                color: rarityColor.withValues(alpha: 0.3),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: rarityColor.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(achievement.icon, style: const TextStyle(fontSize: 24)),
                    LumiGap.horizontalXS,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Almost there!',
                            style: LumiTextStyles.label(color: rarityColor)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                          RichText(
                            text: TextSpan(
                              style: LumiTextStyles.bodySmall(
                                color: AppColors.charcoal.withValues(alpha: 0.8),
                              ),
                              children: [
                                TextSpan(text: '$remaining more $unit to earn '),
                                TextSpan(
                                  text: achievement.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: rarityColor.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ],
                ),
                LumiGap.xs,
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: rarityColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(rarityColor),
                  ),
                ),
                LumiGap.xxs,
                Text(
                  '$current / ${achievement.requiredValue} (${(progress * 100).toStringAsFixed(0)}%)',
                  style: LumiTextStyles.caption(
                    color: AppColors.charcoal.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TodayCard extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final List<AllocationModel> activeAllocations;
  final String? Function(String title)? coverUrlResolver;
  final bool hasLoggedToday;
  final List<ReadingLogModel> todayLogs;

  /// When true the heading names the child — used when several Today cards
  /// are stacked for a multi-child parent (Rec 5b).
  final bool showChildName;

  /// Opens the full detail wizard ("Add detail" / "Log another session").
  final VoidCallback? onTap;

  const _TodayCard({
    required this.student,
    required this.parent,
    this.activeAllocations = const [],
    this.coverUrlResolver,
    required this.hasLoggedToday,
    this.todayLogs = const [],
    this.showChildName = false,
    this.onTap,
  });

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  bool _isQuickLogging = false;

  StudentModel get student => widget.student;
  List<AllocationModel> get activeAllocations => widget.activeAllocations;
  bool get hasLoggedToday => widget.hasLoggedToday;
  List<ReadingLogModel> get todayLogs => widget.todayLogs;
  String? Function(String title)? get coverUrlResolver =>
      widget.coverUrlResolver;
  bool get showChildName => widget.showChildName;
  VoidCallback? get onTap => widget.onTap;

  int get _targetMinutes => activeAllocations.isNotEmpty
      ? activeAllocations.first.targetMinutes
      : 20;

  /// First assigned book title for this student, sanitized for display.
  String? get _firstAssignedTitle {
    for (final allocation in activeAllocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(student.id)) {
        final title = item.title.trim();
        if (title.isNotEmpty) {
          return IsbnAssignmentService.sanitizeDisplayTitle(title);
        }
      }
    }
    return null;
  }

  /// One-line preview of exactly what a single tap will record.
  String get _quickLogSummary {
    final book = _firstAssignedTitle;
    return book != null
        ? '$_targetMinutes min · $book'
        : '$_targetMinutes min of reading';
  }

  /// Records a default reading log for today in a single tap (Rec 1).
  Future<void> _handleQuickLog() async {
    if (_isQuickLogging) return;
    setState(() => _isQuickLogging = true);
    try {
      final result = await ReadingLogService.instance.logReading(
        student: student,
        parent: widget.parent,
        allocations: activeAllocations,
        quickLog: true,
      );
      if (!mounted) return;
      context.go('/parent/reading-success', extra: {
        'student': student,
        'parent': widget.parent,
        'readingLog': result.log,
        'updatedStats': result.updatedStats,
        'freezeUsed': result.freezeUsed,
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't log reading. Please try again."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LumiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: LumiSpacing.xs,
                    vertical: LumiSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    // Rec 10: white-on-#FF8698 fails WCAG AA. Use the
                    // accessible rose for the unread badge, and charcoal
                    // text on the light mint "logged" badge.
                    color: hasLoggedToday
                        ? AppColors.mintGreen
                        : AppColors.rosePinkAccessible,
                    borderRadius: LumiBorders.circular,
                  ),
                  child: Text(
                    DateFormat('EEEE, MMM d').format(DateTime.now()),
                    style: LumiTextStyles.label(
                      color: hasLoggedToday
                          ? AppColors.charcoal
                          : AppColors.white,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasLoggedToday)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.mintGreen,
                    size: 32,
                  ),
              ],
            ),
            LumiGap.m,
            Text(
              showChildName
                  ? (hasLoggedToday
                      ? '${student.firstName} — all done!'
                      : "${student.firstName}'s reading")
                  : (hasLoggedToday
                      ? 'Reading Complete!'
                      : "Today's Reading"),
              style: LumiTextStyles.h2(color: AppColors.charcoal),
            ),
            LumiGap.s,
            if (hasLoggedToday) ...[
              // Show actual minutes logged today (summed across all sessions)
              _buildRequirement(
                context,
                Icons.timer_outlined,
                '${todayLogs.fold<int>(0, (total, log) => total + log.minutesRead)} minutes read today',
              ),
              if (todayLogs.length > 1) ...[
                LumiGap.xs,
                _buildRequirement(
                  context,
                  Icons.repeat,
                  '${todayLogs.length} sessions logged',
                ),
              ],
            ] else if (activeAllocations.isNotEmpty) ...[
              _buildRequirement(
                context,
                Icons.timer_outlined,
                '${activeAllocations.first.targetMinutes} minutes',
              ),
              LumiGap.xs,
              // Collect all book titles from byTitle allocations (deduped)
              Builder(builder: (context) {
                final levelAllocation = activeAllocations
                    .where((a) => a.type == AllocationType.byLevel)
                    .firstOrNull;
                final seen = <String>{};
                final allTitles = activeAllocations
                    .where((a) => a.type == AllocationType.byTitle)
                    .expand(
                      (a) => a
                          .effectiveAssignmentItemsForStudent(student.id)
                          .map((item) => item.title),
                    )
                    .where((t) => t.trim().isNotEmpty)
                    .where((t) => seen.add(t.trim().toLowerCase()))
                    .toList();

                if (levelAllocation == null && allTitles.isEmpty) {
                  final hasFreeChoice = activeAllocations
                      .any((a) => a.type == AllocationType.freeChoice);
                  if (!hasFreeChoice) {
                    return const SizedBox.shrink();
                  }
                  return LumiInfoCard(
                    type: LumiInfoCardType.info,
                    icon: Icons.auto_stories_outlined,
                    title: "This Week's Goal",
                    message: 'Read any book your child enjoys!',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Tonight's Books",
                      style: LumiTextStyles.bodyMedium(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                    LumiGap.xs,
                    if (levelAllocation != null)
                      Padding(
                        padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                        child: LumiBookCard(
                          title:
                              'Level ${levelAllocation.levelStart}${levelAllocation.levelEnd != null ? ' - ${levelAllocation.levelEnd}' : ''}',
                          bookType: BookType.decodable,
                          statusText: 'Assigned',
                        ),
                      ),
                    ...allTitles.map((title) {
                      final displayTitle =
                          IsbnAssignmentService.sanitizeDisplayTitle(title);
                      return Padding(
                        padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                        child: LumiBookCard(
                          title: displayTitle,
                          bookType: BookType.library,
                          statusText: 'Assigned',
                          coverUrl: coverUrlResolver?.call(title),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ] else ...[
              _buildRequirement(
                context,
                Icons.timer_outlined,
                '20 minutes',
              ),
              LumiGap.xs,
              _buildRequirement(
                context,
                Icons.book_outlined,
                'Any reading material',
              ),
            ],
            LumiGap.m,
            if (hasLoggedToday)
              SizedBox(
                width: double.infinity,
                child: LumiPrimaryButton(
                  onPressed: onTap,
                  text: 'Log Another Session',
                  icon: Icons.add_circle_outline,
                ),
              )
            else ...[
              // Rec 1: one-tap log is the default action. The caption tells
              // the parent exactly what a single tap will record.
              Text(
                'One tap logs $_quickLogSummary',
                style: LumiTextStyles.caption(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
              LumiGap.xs,
              LumiPrimaryButton(
                onPressed: _isQuickLogging ? null : _handleQuickLog,
                isLoading: _isQuickLogging,
                isFullWidth: true,
                text: 'Did ${student.firstName} read today?',
                icon: Icons.check_circle_outline,
              ),
              LumiGap.xxs,
              Center(
                child: LumiTextButton(
                  onPressed: _isQuickLogging ? null : onTap,
                  text: 'Add detail',
                  icon: Icons.tune,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRequirement(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.charcoal.withValues(alpha: 0.7),
        ),
        LumiGap.horizontalXS,
        Expanded(
          child: Text(
            text,
            style: LumiTextStyles.bodyLarge(color: AppColors.charcoal),
          ),
        ),
      ],
    );
  }
}

class _ProgressAndWeekSection extends ConsumerWidget {
  final String studentId;
  final String schoolId;

  const _ProgressAndWeekSection({
    required this.studentId,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    final firebaseService = ref.read(firebaseServiceProvider);

    return StreamBuilder<QuerySnapshot>(
      stream: firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: studentId)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .snapshots(),
      builder: (context, snapshot) {
        final logs = <ReadingLogModel>[];
        if (snapshot.hasData) {
          logs.addAll(
            snapshot.data!.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc)),
          );
        }

        final completedDays = <int>{};
        for (final log in logs) {
          final dayOfWeek = log.date.weekday; // 1=Mon, 7=Sun
          completedDays.add(dayOfWeek);
        }

        final todayComplete = completedDays.contains(DateTime.now().weekday);

        return Column(
          children: [
            // Progress Ring Card
            StreamBuilder<DocumentSnapshot>(
              stream: firebaseService.firestore
                  .collection('schools')
                  .doc(schoolId)
                  .collection('students')
                  .doc(studentId)
                  .snapshots(),
              builder: (context, studentSnapshot) {
                int totalNights = 0;
                int currentStreak = 0;
                if (studentSnapshot.hasData && studentSnapshot.data!.exists) {
                  final student =
                      StudentModel.fromFirestore(studentSnapshot.data!);
                  totalNights = student.stats?.totalReadingDays ?? 0;
                  currentStreak = student.stats?.currentStreak ?? 0;
                }

                return LumiCard(
                  child: Column(
                    children: [
                      ProgressRing(
                        totalNights: totalNights,
                        weeklyProgress: completedDays.length,
                        todayComplete: todayComplete,
                      ),
                      LumiGap.s,
                      if (currentStreak > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.local_fire_department,
                              color: AppColors.rosePink,
                              size: 20,
                            ),
                            LumiGap.horizontalXXS,
                            Text(
                              '$currentStreak day streak!',
                              style: LumiTextStyles.bodyMedium(
                                color: AppColors.rosePink,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),

            LumiGap.m,

            // Week Progress Card
            LumiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This Week',
                    style: LumiTextStyles.h2(color: AppColors.charcoal),
                  ),
                  LumiGap.m,
                  WeekProgressBar(
                    completedDays: completedDays,
                    currentDay: DateTime.now().weekday,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Owns the per-child Today card and its Firestore streams (today's logs +
/// active allocations). Encapsulating the streams here lets ParentHomeScreen
/// render one card per child (Rec 5b) without the build method juggling 3N
/// listeners — each card starts and stops its own subscriptions with its
/// own lifecycle.
class _ChildTodayCard extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final bool showChildName;

  const _ChildTodayCard({
    required this.student,
    required this.parent,
    this.showChildName = false,
  });

  @override
  State<_ChildTodayCard> createState() => _ChildTodayCardState();
}

class _ChildTodayCardState extends State<_ChildTodayCard> {
  late final Stream<QuerySnapshot> _todayLogsStream;
  late final Stream<List<QuerySnapshot>> _allocationsStream;

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseService.instance.firestore;
    final schoolId = widget.parent.schoolId;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    _todayLogsStream = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: widget.student.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('date', descending: true)
        .snapshots();

    // Allocations targeting this student specifically …
    final studentAllocations = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('studentIds', arrayContains: widget.student.id)
        .where('isActive', isEqualTo: true)
        .snapshots();

    // … and whole-class allocations (empty studentIds).
    final classAllocations = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: widget.student.classId)
        .where('studentIds', isEqualTo: [])
        .where('isActive', isEqualTo: true)
        .snapshots();

    _allocationsStream = _combineStreams(studentAllocations, classAllocations);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _todayLogsStream,
      builder: (context, logSnapshot) {
        final todayLogs = logSnapshot.hasData
            ? logSnapshot.data!.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList()
            : <ReadingLogModel>[];
        final hasLoggedToday = todayLogs.isNotEmpty;

        return StreamBuilder<List<QuerySnapshot>>(
          stream: _allocationsStream,
          builder: (context, allocationSnapshot) {
            final activeAllocations = <AllocationModel>[];
            if (allocationSnapshot.hasData) {
              final now = DateTime.now();
              final seen = <String>{};
              for (final doc
                  in allocationSnapshot.data!.expand((qs) => qs.docs)) {
                if (!seen.add(doc.id)) continue;
                final candidate = AllocationModel.fromFirestore(doc);
                if (candidate.startDate.isBefore(now) &&
                    candidate.endDate.isAfter(now)) {
                  activeAllocations.add(candidate);
                }
              }
            }
            BookCoverCacheService.instance.primeFromAllocations(
              activeAllocations,
              FirebaseService.instance.firestore,
            );

            return _TodayCard(
              student: widget.student,
              parent: widget.parent,
              activeAllocations: activeAllocations,
              coverUrlResolver: BookCoverCacheService.instance.resolveCoverUrl,
              hasLoggedToday: hasLoggedToday,
              todayLogs: todayLogs,
              showChildName: widget.showChildName,
              onTap: () {
                NavigationStateService().setTempData({
                  'parent': widget.parent,
                  'student': widget.student,
                  'allocations': activeAllocations,
                });
                context.push('/parent/log-reading');
              },
            );
          },
        );
      },
    );
  }
}

/// Merges two Firestore query streams into one stream that emits the latest
/// pair whenever either side updates.
Stream<List<QuerySnapshot>> _combineStreams(
  Stream<QuerySnapshot> stream1,
  Stream<QuerySnapshot> stream2,
) {
  QuerySnapshot? latest1;
  QuerySnapshot? latest2;
  late final StreamController<List<QuerySnapshot>> controller;
  StreamSubscription? sub1;
  StreamSubscription? sub2;

  controller = StreamController<List<QuerySnapshot>>(
    onListen: () {
      sub1 = stream1.listen((snapshot) {
        latest1 = snapshot;
        if (latest2 != null) controller.add([latest1!, latest2!]);
      });
      sub2 = stream2.listen((snapshot) {
        latest2 = snapshot;
        if (latest1 != null) controller.add([latest1!, latest2!]);
      });
    },
    onCancel: () {
      sub1?.cancel();
      sub2?.cancel();
    },
  );

  return controller.stream;
}
