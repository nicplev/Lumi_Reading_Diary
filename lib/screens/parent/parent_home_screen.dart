import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../theme/section_theme.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/week_progress_bar.dart';
import '../../core/widgets/lumi/lumi_book_card.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/services/navigation_state_service.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/providers/active_child_provider.dart';
import '../../data/providers/user_provider.dart';
import '../../services/book_cover_cache_service.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/reading_log_service.dart';
import '../../services/widget_data_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/staff_notification_service.dart';
import '../../services/logging_engagement_service.dart';
import 'reading_history_screen.dart';
import 'parent_profile_screen.dart';
import 'widgets/add_email_for_recovery_modal.dart';
import 'widgets/parent_child_switcher.dart';
import 'widgets/widget_undo_banner.dart';

/// Vertical space the floating glass nav occupies above the safe-area inset.
/// Scroll content reserves this so the last item clears the bar.
const double _kNavBarClearance = 92;

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
    _consumePendingReminderDeepLink();
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
    // was backgrounded. Reminder suppression for already-logged-today is now
    // handled server-side by the `sendReadingReminders` Cloud Function.
    if (state == AppLifecycleState.resumed) {
      final children = ref.read(parentChildrenProvider).value;
      if (children != null && children.isNotEmpty) {
        WidgetDataService.instance.drainPendingWidgetLogs(
          children: children,
          parent: widget.user,
        );
      }
      _consumePendingReminderDeepLink();
    }
  }

  /// If the user just tapped a reading-reminder notification,
  /// NotificationService stored the child id in SharedPreferences. Adopt it
  /// as the active child so logging that child's reading is one tap away,
  /// then clear the key so it can't replay on a later cold start.
  Future<void> _consumePendingReminderDeepLink() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingId = prefs.getString(NotificationService.pendingLogChildIdKey);
    if (pendingId == null || pendingId.isEmpty) return;
    await prefs.remove(NotificationService.pendingLogChildIdKey);
    if (!mounted) return;
    await ref.read(activeChildIdProvider.notifier).select(pendingId);
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
            backgroundColor: LumiTokens.cream,
            body: Center(
              child: CircularProgressIndicator(color: LumiTokens.red),
            ),
          ),
          error: (_, __) => Scaffold(
            backgroundColor: LumiTokens.cream,
            body: _buildErrorView(),
          ),
          data: (children) {
            if (children.isEmpty) {
              return Scaffold(
                backgroundColor: LumiTokens.cream,
                body: _buildNoChildrenView(),
              );
            }
            final activeChild =
                ref.watch(activeChildProvider).value ?? children.first;
            return Scaffold(
              backgroundColor: LumiTokens.cream,
              body: Stack(
                children: [
                  Column(
                    children: [
                      // In-app undo banner — Layer 2 of the widget undo flow.
                      // Self-hides when no recent widget commit is in window.
                      // Sits above the IndexedStack so it's visible on every
                      // parent tab during the ~5-minute undo window.
                      const SafeArea(
                        bottom: false,
                        child: WidgetUndoBanner(),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: [
                            // Home section (red). Its scroll content adds its
                            // own bottom clearance so it scrolls behind the
                            // floating glass nav.
                            LumiSectionScope(
                              section: LumiSectionTheme.home,
                              child: _buildHomeView(activeChild, children),
                            ),
                            // Library section (yellow). Its scroll views add
                            // their own bottom clearance so it scrolls behind
                            // the floating glass nav, just like Home.
                            LumiSectionScope(
                              section: LumiSectionTheme.library,
                              child: ReadingHistoryScreen(
                                // Re-key on the active child so a switch rebuilds
                                // the Bookshelf with fresh state, not stale data.
                                key: ValueKey(activeChild.id),
                                studentId: activeChild.id,
                                parentId: widget.user.id,
                                schoolId: widget.user.schoolId!,
                              ),
                            ),
                            // Settings section (green). Owns its bottom
                            // clearance so it scrolls behind the glass nav.
                            LumiSectionScope(
                              section: LumiSectionTheme.settings,
                              child: ParentProfileScreen(user: widget.user),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.only(bottom: 8),
                      child: _buildBottomNav(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }

  Widget _buildBottomNav() {
    // The parent app has three sections (design guide A1):
    // Home = red, Library = yellow, Settings = green. The active tab adopts
    // its section's colour. Floating glassmorphic bar matching the teacher app.
    const navItems = <({IconData icon, String label, Color color})>[
      (icon: Icons.home_outlined, label: 'Home', color: LumiTokens.red),
      (
        icon: Icons.auto_stories_outlined,
        label: 'Library',
        color: LumiTokens.yellow
      ),
      (icon: Icons.settings_outlined, label: 'Settings', color: LumiTokens.green),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: LumiTokens.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: LumiTokens.paper.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: LumiTokens.paper.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (int i = 0; i < navItems.length; i++)
                  Expanded(
                    child: _ParentNavItem(
                      icon: navItems[i].icon,
                      label: navItems[i].label,
                      isSelected: _selectedIndex == i,
                      onTap: () => setState(() => _selectedIndex = i),
                      selectedColor: navItems[i].color,
                      unselectedColor: LumiTokens.muted,
                    ),
                  ),
              ],
            ),
          ),
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
              color: LumiTokens.muted,
            ),
            LumiGap.s,
            Text(
              'Couldn\'t load your children',
              style: LumiType.subhead,
              textAlign: TextAlign.center,
            ),
            LumiGap.xs,
            Text(
              'Please check your connection and try again.',
              style: LumiType.bodyL.copyWith(color: LumiTokens.muted),
              textAlign: TextAlign.center,
            ),
            LumiGap.m,
            LumiPrimaryButton(
              onPressed: () => ref.invalidate(parentChildrenProvider),
              text: 'Retry',
              icon: Icons.refresh,
              color: LumiTokens.red,
            ),
          ],
        ),
      ),
    );
  }

  /// Whether the account has an email — either the (possibly stale) model
  /// email or the live Firebase Auth email, which updates within moments of an
  /// email being linked. Read during build so the recovery nudge reacts
  /// without an app restart or re-login.
  bool get _accountHasEmail {
    final modelEmail = (widget.user.email ?? '').trim();
    final liveEmail = (ref.watch(authEmailProvider) ?? '').trim();
    return modelEmail.isNotEmpty || liveEmail.isNotEmpty;
  }

  Widget _buildRecoveryBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: LumiTokens.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: InkWell(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          onTap: () =>
              AddEmailForRecoveryModal.show(context: context, user: widget.user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18,
                    color: LumiTokens.red.withValues(alpha: 0.9)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add an email so you can get back in if you lose your phone',
                    style: LumiType.body.copyWith(
                      fontSize: 14,
                      color: LumiTokens.ink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: LumiTokens.ink.withValues(alpha: 0.5)),
              ],
            ),
          ),
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
            title: Text(
              'Hello, ${widget.user.fullName.isNotEmpty ? widget.user.fullName.split(' ').first : 'Parent'}',
              style: LumiType.heading,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: StreamBuilder<int>(
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
                              color: LumiTokens.red,
                              borderRadius:
                                  BorderRadius.circular(LumiTokens.radiusPill),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: LumiType.caption.copyWith(
                                color: LumiTokens.paper,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                ),
              ),
            ],
          ),

          // Persistent child switcher — renders only for 2+ children.
          const SliverToBoxAdapter(child: ParentChildSwitcher()),

          // Quiet recovery nudge for phone-only parents — disappears the
          // moment they finish the add-email flow. The model email is a stale
          // one-time read (userProvider doesn't re-fetch when an email is
          // linked mid-session), so we also watch the live Firebase Auth email
          // via authEmailProvider; either one being present hides the nudge.
          if (!_accountHasEmail) SliverToBoxAdapter(child: _buildRecoveryBanner()),

          // Content
          SliverPadding(
            padding: LumiPadding.allS,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Occasional, purpose-framed nudge toward the richer flow.
                // Self-hides unless it's a good moment (cadence-limited).
                const _FullFlowNudge(),

                // Tonight — the one thing to do. A single child gets the clear
                // big-button card; a multi-child parent gets one card with a
                // tap-to-log row per child, so every child can be logged
                // without switching context.
                if (children.length == 1)
                  _ChildTodayCard(
                    student: children.first,
                    parent: widget.user,
                  ).animate().fadeIn().scale()
                else
                  _TonightMultiCard(
                    children: children,
                    parent: widget.user,
                  ).animate().fadeIn(),

                LumiGap.m,

                // One calm momentum card for the active child. Taps through to
                // the full Progress screen (stats, rhythm, achievements).
                _MomentumCard(
                  student: selectedChild,
                ).animate().fadeIn(delay: 100.ms),
              ]),
            ),
          ),
          // Clearance so the last card scrolls clear of the floating nav.
          const SliverToBoxAdapter(
            child: SizedBox(height: _kNavBarClearance),
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
              style: LumiType.heading,
            ),
            LumiGap.xs,
            Text(
              'Please ask your teacher for an invite code to link your children.',
              style: LumiType.bodyL.copyWith(color: LumiTokens.muted),
              textAlign: TextAlign.center,
            ),
            LumiGap.l,
            LumiPrimaryButton(
              onPressed: () => context.push('/parent/link-child'),
              text: 'Enter Invite Code',
              icon: Icons.qr_code,
              color: LumiTokens.red,
            ),
          ],
        ),
      ),
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

  /// Opens the full detail wizard ("Add detail" / "Log another session").
  final VoidCallback? onTap;

  const _TodayCard({
    required this.student,
    required this.parent,
    this.activeAllocations = const [],
    this.coverUrlResolver,
    required this.hasLoggedToday,
    this.todayLogs = const [],
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
        'restDayApplied': result.restDayApplied,
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
                    // Logged = soft green tint with ink text; not-yet-logged =
                    // the Home red accent with white text. Both clear WCAG AA.
                    color: hasLoggedToday
                        ? LumiTokens.tintGreen
                        : LumiTokens.red,
                    borderRadius: LumiBorders.circular,
                  ),
                  child: Text(
                    DateFormat('EEEE, MMM d').format(DateTime.now()),
                    style: LumiType.caption.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: hasLoggedToday
                          ? LumiTokens.ink
                          : LumiTokens.paper,
                    ),
                  ),
                ),
                const Spacer(),
                if (hasLoggedToday)
                  const Icon(
                    Icons.check_circle,
                    color: LumiTokens.green,
                    size: 32,
                  ),
              ],
            ),
            LumiGap.m,
            Text(
              hasLoggedToday
                  ? '${student.firstName} — all done!'
                  : "${student.firstName}'s reading",
              style: LumiType.subhead,
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
                      style: LumiType.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: LumiTokens.muted,
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
                  color: LumiTokens.red,
                ),
              )
            else ...[
              // Rec 1: one-tap log is the default action. The caption tells
              // the parent exactly what a single tap will record.
              Text(
                'One tap logs $_quickLogSummary',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.ink.withValues(alpha: 0.6),
                ),
              ),
              LumiGap.xs,
              LumiPrimaryButton(
                onPressed: _isQuickLogging ? null : _handleQuickLog,
                isLoading: _isQuickLogging,
                isFullWidth: true,
                text: 'Did ${student.firstName} read today?',
                icon: Icons.check_circle_outline,
                color: LumiTokens.red,
              ),
              LumiGap.xxs,
              Center(
                child: LumiTextButton(
                  onPressed: _isQuickLogging ? null : onTap,
                  text: 'Add detail',
                  icon: Icons.tune,
                  color: LumiTokens.red,
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
          color: LumiTokens.muted,
        ),
        LumiGap.horizontalXS,
        Expanded(
          child: Text(
            text,
            style: LumiType.bodyL,
          ),
        ),
      ],
    );
  }
}

/// The next cumulative-nights milestone above [totalNights] — drives the
/// progress ring's outer goal so it always tracks progress to the next badge
/// rather than a flat 100.
int _nextNightsGoal(int totalNights) {
  for (final threshold in AchievementThresholds.defaults.readingDays) {
    if (threshold > totalNights) return threshold;
  }
  // Past the top badge — keep the ring meaningful with the next round century.
  return ((totalNights ~/ 100) + 1) * 100;
}

/// Owns the per-child Today card and its Firestore streams (today's logs +
/// active allocations). Encapsulating the streams here lets ParentHomeScreen
/// render one card per child (Rec 5b) without the build method juggling 3N
/// listeners — each card starts and stops its own subscriptions with its
/// own lifecycle.
class _ChildTodayCard extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;

  const _ChildTodayCard({
    required this.student,
    required this.parent,
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

    // Broadcast so a StreamBuilder that re-subscribes (rebuild / reinsertion)
    // doesn't trip "Stream has already been listened to" on this single-
    // subscription Firestore stream.
    _todayLogsStream = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: widget.student.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('date', descending: true)
        .snapshots()
        .asBroadcastStream();

    // Allocations targeting this student specifically …
    Stream<QuerySnapshot> studentAllocations() => firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('studentIds', arrayContains: widget.student.id)
        .where('isActive', isEqualTo: true)
        .snapshots();

    // … and whole-class allocations (empty studentIds).
    Stream<QuerySnapshot> classAllocations() => firestore
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

/// One calm momentum card for the active child: cumulative nights (the hero),
/// a gentle streak chip (only when positive — cheer, don't shame), the week at
/// a glance, and forward progress to the next badge. Taps through to the full
/// Progress screen. Replaces the old ring + stats + rhythm + near-miss stack.
class _MomentumCard extends StatelessWidget {
  final StudentModel student;

  const _MomentumCard({required this.student});

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseService.instance.firestore;
    final accent = context.sectionTheme.accent;
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    return GestureDetector(
      onTap: () =>
          context.push('/parent/progress', extra: {'student': student}),
      child: LumiCard(
        child: StreamBuilder<DocumentSnapshot>(
          stream: firestore
              .collection('schools')
              .doc(student.schoolId)
              .collection('students')
              .doc(student.id)
              .snapshots(),
          builder: (context, studentSnap) {
            int totalNights = 0;
            int currentStreak = 0;
            if (studentSnap.hasData && studentSnap.data!.exists) {
              final stats =
                  StudentModel.fromFirestore(studentSnap.data!).stats;
              totalNights = stats?.totalReadingDays ?? 0;
              currentStreak = stats?.currentStreak ?? 0;
            }
            final nextGoal = _nextNightsGoal(totalNights);
            final remaining = (nextGoal - totalNights).clamp(0, nextGoal);
            final progress =
                nextGoal == 0 ? 0.0 : (totalNights / nextGoal).clamp(0.0, 1.0);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('$totalNights', style: LumiType.numberLarge),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        totalNights == 1 ? 'night' : 'nights',
                        style: LumiType.body.copyWith(color: LumiTokens.muted),
                      ),
                    ),
                    const Spacer(),
                    // Streak is gentle and secondary — and only shows when it's
                    // something to celebrate (never a sad "0").
                    if (currentStreak > 0) ...[
                      Icon(
                        Icons.local_fire_department,
                        color: LumiTokens.orange.withValues(alpha: 0.85),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$currentStreak-day',
                        style: LumiType.body
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Icon(Icons.chevron_right_rounded,
                        color: LumiTokens.muted),
                  ],
                ),
                LumiGap.m,
                // This week, at a glance.
                StreamBuilder<QuerySnapshot>(
                  stream: firestore
                      .collection('schools')
                      .doc(student.schoolId)
                      .collection('readingLogs')
                      .where('studentId', isEqualTo: student.id)
                      .where('date',
                          isGreaterThanOrEqualTo:
                              Timestamp.fromDate(startOfWeek))
                      .snapshots(),
                  builder: (context, weekSnap) {
                    final completedDays = <int>{};
                    if (weekSnap.hasData) {
                      for (final doc in weekSnap.data!.docs) {
                        completedDays
                            .add(ReadingLogModel.fromFirestore(doc).date.weekday);
                      }
                    }
                    return WeekProgressBar(
                      completedDays: completedDays,
                      currentDay: now.weekday,
                    );
                  },
                ),
                LumiGap.m,
                // Forward progress to the next badge — the only goal we surface.
                ClipRRect(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: accent.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  remaining <= 0
                      ? 'Next badge unlocked'
                      : '$remaining ${remaining == 1 ? 'night' : 'nights'} to your next badge',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tonight, for a multi-child parent: one card, a tap-to-log row per child so
/// every child can be logged without switching context.
class _TonightMultiCard extends StatelessWidget {
  final List<StudentModel> children;
  final UserModel parent;

  const _TonightMultiCard({required this.children, required this.parent});

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: LumiSpacing.xs,
              vertical: LumiSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: LumiTokens.red,
              borderRadius: LumiBorders.circular,
            ),
            child: Text(
              DateFormat('EEEE, MMM d').format(DateTime.now()),
              style: LumiType.caption.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: LumiTokens.paper,
              ),
            ),
          ),
          LumiGap.s,
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: LumiTokens.rule),
            _TonightRow(student: children[i], parent: parent),
          ],
          LumiGap.xs,
          // Teach both gestures: the row opens the richer flow, the circle is
          // the one-tap shortcut.
          Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 14, color: LumiTokens.muted.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tap a name to add how it went · tap the circle to log fast',
                  style: LumiType.caption.copyWith(
                    color: LumiTokens.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single child's tap-to-log row. Owns its own today-logs + allocations
/// streams (mirrors [_ChildTodayCard]); tap the circle to one-tap log, tap the
/// row to open the full detail flow.
class _TonightRow extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;

  const _TonightRow({required this.student, required this.parent});

  @override
  State<_TonightRow> createState() => _TonightRowState();
}

class _TonightRowState extends State<_TonightRow> {
  late final Stream<QuerySnapshot> _todayLogsStream;
  late final Stream<List<QuerySnapshot>> _allocationsStream;
  bool _isQuickLogging = false;

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
        .snapshots()
        .asBroadcastStream();

    Stream<QuerySnapshot> studentAllocations() => firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('studentIds', arrayContains: widget.student.id)
        .where('isActive', isEqualTo: true)
        .snapshots();

    Stream<QuerySnapshot> classAllocations() => firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('classId', isEqualTo: widget.student.classId)
        .where('studentIds', isEqualTo: [])
        .where('isActive', isEqualTo: true)
        .snapshots();

    _allocationsStream = _combineStreams(studentAllocations, classAllocations);
  }

  List<AllocationModel> _activeFrom(
      AsyncSnapshot<List<QuerySnapshot>> snapshot) {
    final result = <AllocationModel>[];
    if (snapshot.hasData) {
      final now = DateTime.now();
      final seen = <String>{};
      for (final doc in snapshot.data!.expand((qs) => qs.docs)) {
        if (!seen.add(doc.id)) continue;
        final candidate = AllocationModel.fromFirestore(doc);
        if (candidate.startDate.isBefore(now) &&
            candidate.endDate.isAfter(now)) {
          result.add(candidate);
        }
      }
    }
    return result;
  }

  String _summary(List<AllocationModel> allocations) {
    final target =
        allocations.isNotEmpty ? allocations.first.targetMinutes : 20;
    String? book;
    for (final allocation in allocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(widget.student.id)) {
        final title = item.title.trim();
        if (title.isNotEmpty) {
          book = IsbnAssignmentService.sanitizeDisplayTitle(title);
          break;
        }
      }
      if (book != null) break;
    }
    return book != null ? '$target min · $book' : '$target min · Any book';
  }

  Future<void> _quickLog(List<AllocationModel> allocations) async {
    if (_isQuickLogging) return;
    setState(() => _isQuickLogging = true);
    try {
      final result = await ReadingLogService.instance.logReading(
        student: widget.student,
        parent: widget.parent,
        allocations: allocations,
        quickLog: true,
      );
      if (!mounted) return;
      context.go('/parent/reading-success', extra: {
        'student': widget.student,
        'parent': widget.parent,
        'readingLog': result.log,
        'updatedStats': result.updatedStats,
        'restDayApplied': result.restDayApplied,
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

  void _openDetail(List<AllocationModel> allocations) {
    NavigationStateService().setTempData({
      'parent': widget.parent,
      'student': widget.student,
      'allocations': allocations,
    });
    context.push('/parent/log-reading');
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
            final allocations = _activeFrom(allocationSnapshot);
            BookCoverCacheService.instance.primeFromAllocations(
              allocations,
              FirebaseService.instance.firestore,
            );
            // A "full" entry: feeling, a recording, or a note was added —
            // earns a gentle mark (positive recognition; quick logs are never
            // penalised for its absence).
            final hasDetail = todayLogs.any((log) =>
                log.childFeeling != null ||
                log.comprehensionAudioPath != null ||
                (log.parentComment != null && log.parentComment!.isNotEmpty));

            return InkWell(
              onTap:
                  _isQuickLogging ? null : () => _openDetail(allocations),
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    StudentAvatar.fromStudent(widget.student, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.student.firstName,
                            style: LumiType.body
                                .copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (hasLoggedToday && hasDetail) ...[
                                const Icon(Icons.auto_awesome,
                                    size: 12, color: LumiTokens.green),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  hasLoggedToday
                                      ? '${todayLogs.fold<int>(0, (total, log) => total + log.minutesRead)} min read today'
                                      : _summary(allocations),
                                  style: LumiType.caption
                                      .copyWith(color: LumiTokens.muted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Chevron signals the row opens the full detail flow —
                    // the richer path. The circle beside it is the shortcut.
                    const Icon(Icons.chevron_right_rounded,
                        color: LumiTokens.muted, size: 20),
                    const SizedBox(width: 6),
                    _LogCircle(
                      done: hasLoggedToday,
                      loading: _isQuickLogging,
                      onTap: hasLoggedToday || _isQuickLogging
                          ? null
                          : () => _quickLog(allocations),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The tap target on a Tonight row: a hollow red ring before logging, a filled
/// green check once done, a spinner mid-log.
class _LogCircle extends StatelessWidget {
  final bool done;
  final bool loading;
  final VoidCallback? onTap;

  const _LogCircle({
    required this.done,
    required this.loading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Widget inner;
    if (loading) {
      inner = const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: LumiTokens.red,
        ),
      );
    } else if (done) {
      inner = Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: LumiTokens.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            color: LumiTokens.paper, size: 24),
      );
    } else {
      inner = Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: LumiTokens.red, width: 2),
        ),
        child: Icon(Icons.check_rounded,
            color: LumiTokens.red.withValues(alpha: 0.35), size: 22),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 44, height: 44, child: Center(child: inner)),
    );
  }
}

/// An occasional, dismissible nudge toward the richer logging flow. Decides
/// once on init whether this is a good moment (weekend / been-a-while, and not
/// nudged recently) and self-hides otherwise — it must never feel like nagging.
class _FullFlowNudge extends StatefulWidget {
  const _FullFlowNudge();

  @override
  State<_FullFlowNudge> createState() => _FullFlowNudgeState();
}

class _FullFlowNudgeState extends State<_FullFlowNudge> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    LoggingEngagementService.instance.shouldShowFullFlowNudge().then((show) {
      if (!mounted || !show) return;
      LoggingEngagementService.instance.markNudgeShown();
      setState(() => _show = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: LumiSpacing.s),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: LumiTokens.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.red.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.favorite_outline_rounded,
              size: 18, color: LumiTokens.red.withValues(alpha: 0.9)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Got a minute tonight? Adding how the reading went helps your "
              "child's teacher see how it's going.",
              style: LumiType.caption.copyWith(
                fontSize: 13,
                color: LumiTokens.ink.withValues(alpha: 0.85),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _show = false),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.close_rounded,
                  size: 18, color: LumiTokens.muted),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

/// A single item in the floating glass bottom nav. Mirrors the teacher app's
/// nav item: icon + caption, tinted with the section colour when active.
class _ParentNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color unselectedColor;

  const _ParentNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.selectedColor,
    required this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : unselectedColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(child: Icon(icon, size: 24, color: color)),
          ),
          const SizedBox(height: 1),
          Text(label, style: LumiType.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Merges two Firestore query streams into one stream that emits the latest
/// pair whenever either side updates.
///
/// Takes stream *factories* (not streams) and exposes a broadcast stream so the
/// result can be safely re-listened: each fresh subscription opens its own
/// `.snapshots()` subscriptions. Passing already-created single-subscription
/// Firestore streams here would throw "Stream has already been listened to" the
/// moment a StreamBuilder re-subscribes (rebuild / reinsertion).
Stream<List<QuerySnapshot>> _combineStreams(
  Stream<QuerySnapshot> Function() factory1,
  Stream<QuerySnapshot> Function() factory2,
) {
  QuerySnapshot? latest1;
  QuerySnapshot? latest2;
  late final StreamController<List<QuerySnapshot>> controller;
  StreamSubscription? sub1;
  StreamSubscription? sub2;

  controller = StreamController<List<QuerySnapshot>>.broadcast(
    onListen: () {
      latest1 = null;
      latest2 = null;
      sub1 = factory1().listen((snapshot) {
        latest1 = snapshot;
        if (latest2 != null) controller.add([latest1!, latest2!]);
      });
      sub2 = factory2().listen((snapshot) {
        latest2 = snapshot;
        if (latest1 != null) controller.add([latest1!, latest2!]);
      });
    },
    onCancel: () {
      sub1?.cancel();
      sub2?.cancel();
      sub1 = null;
      sub2 = null;
    },
  );

  return controller.stream;
}
