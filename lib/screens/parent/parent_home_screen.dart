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
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/tour/lumi_app_tour.dart';
import '../../core/services/navigation_state_service.dart';
import '../../core/utils/motion.dart';
import '../../core/utils/school_time.dart';
import '../../data/providers/school_time_provider.dart';
import '../../data/models/achievement_model.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/providers/active_child_provider.dart';
import '../../data/providers/school_settings_provider.dart';
import '../../data/providers/user_provider.dart';
import '../../services/book_cover_cache_service.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/offline_service.dart';
import '../../services/reading_log_service.dart';
import '../../services/widget_data_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/staff_notification_service.dart';
import '../../services/logging_engagement_service.dart';
import 'reading_history_screen.dart';
import 'widgets/award_celebration_dialog.dart';
import 'parent_profile_screen.dart';
import 'widgets/add_email_for_recovery_modal.dart';
import 'widgets/character_picker_sheet.dart';
import 'widgets/parent_child_switcher.dart';
import 'widgets/widget_undo_banner.dart';
import 'widgets/child_log_row.dart';
import 'widgets/pending_session_sheet.dart';
import 'widgets/today_sessions_sheet.dart';
import 'parent_logging_copy.dart';

/// Vertical space the floating glass nav occupies above the safe-area inset.
/// Scroll content reserves this so the last item clears the bar.
const double _kNavBarClearance = 92;

class ParentHomeScreen extends ConsumerStatefulWidget {
  final UserModel user;
  final String? widgetChildId;
  final String? widgetAction;
  final String? widgetTapId;
  final bool promptForCharacterOnEntry;

  const ParentHomeScreen({
    super.key,
    required this.user,
    this.widgetChildId,
    this.widgetAction,
    this.widgetTapId,
    this.promptForCharacterOnEntry = false,
  });

  @override
  ConsumerState<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends ConsumerState<ParentHomeScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _handledWidgetDeepLink = false;
  bool _characterPromptScheduled = false;
  bool _firstLoginCharacterPromptCompleted = false;
  bool _parentTourScheduled = false;
  // Award celebration: guards against re-entrancy while a modal is being
  // resolved/shown, plus the set of award keys already handled this session.
  bool _awardCelebrationInFlight = false;
  final Set<String> _celebratedAwardKeysThisSession = <String>{};
  final LumiTourController _tourController = LumiTourController();

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
  void didUpdateWidget(covariant ParentHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.widgetChildId != widget.widgetChildId ||
        oldWidget.widgetAction != widget.widgetAction ||
        oldWidget.widgetTapId != widget.widgetTapId) {
      _handledWidgetDeepLink = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BookCoverCacheService.instance.removeListener(_onCoversUpdated);
    _tourController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final children = ref.read(parentChildrenProvider).value;
      if (children != null && children.isNotEmpty) {
        // Clears any legacy AppIntent queue from older widget builds. Current
        // widget taps deep-link into the app instead of writing from the widget.
        WidgetDataService.instance.drainPendingWidgetLogs(
          children: children,
          parent: widget.user,
        );
      }
      _consumePendingReminderDeepLink();
    }
  }

  /// If the user just tapped a reading-reminder notification,
  /// NotificationService stored the prompted child id(s) in SharedPreferences.
  /// Seed the reminder queue (so a multi-child parent is guided through each
  /// child after logging) and adopt the first as the active child, then clear
  /// the keys so they can't replay on a later cold start.
  Future<void> _consumePendingReminderDeepLink() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingId = prefs.getString(NotificationService.pendingLogChildIdKey);
    final pendingIds =
        prefs.getStringList(NotificationService.pendingLogChildIdsKey);
    final ids = (pendingIds != null && pendingIds.isNotEmpty)
        ? pendingIds
        : <String>[if (pendingId != null && pendingId.isNotEmpty) pendingId];
    if (ids.isEmpty) return;
    await prefs.remove(NotificationService.pendingLogChildIdKey);
    await prefs.remove(NotificationService.pendingLogChildIdsKey);
    if (!mounted) return;
    ref.read(pendingReminderChildIdsProvider.notifier).setAll(ids);
    await ref.read(activeChildIdProvider.notifier).select(ids.first);
  }

  void _scheduleWidgetDeepLinkHandling(List<StudentModel> children) {
    if (_handledWidgetDeepLink) return;
    final action = widget.widgetAction;
    final hasWidgetRoute = action == 'log' ||
        action == 'home' ||
        (widget.widgetChildId?.trim().isNotEmpty ?? false);
    if (!hasWidgetRoute) return;

    _handledWidgetDeepLink = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_handleWidgetDeepLink(children));
    });
  }

  Future<void> _handleWidgetDeepLink(List<StudentModel> children) async {
    final action = widget.widgetAction == 'log' ? 'log' : 'home';
    final requestedChildId = widget.widgetChildId?.trim() ?? '';
    StudentModel? targetChild;

    if (requestedChildId.isNotEmpty) {
      for (final child in children) {
        if (child.id == requestedChildId) {
          targetChild = child;
          break;
        }
      }
      if (targetChild == null) {
        debugPrint('[ParentHomeScreen] ignored widget link for unknown child: '
            '$requestedChildId');
        return;
      }
    } else {
      targetChild = ref.read(activeChildProvider).value ?? children.first;
    }

    await ref.read(activeChildIdProvider.notifier).select(targetChild.id);
    if (!mounted) return;
    if (_selectedIndex != 0) {
      setState(() => _selectedIndex = 0);
    }
    if (action != 'log') return;

    final alreadyLogged = await _hasReadingLogToday(targetChild);
    if (!mounted || alreadyLogged) return;

    final allocations = await _loadActiveAllocationsFor(targetChild);
    if (!mounted) return;
    NavigationStateService().setTempData({
      'parent': widget.user,
      'student': targetChild,
      'allocations': allocations,
    });
    context.push('/parent/log-reading');
  }

  Future<void> _showReadingHistoryFor(StudentModel student) async {
    await ref.read(activeChildIdProvider.notifier).select(student.id);
    if (!mounted || _selectedIndex == 1) return;
    setState(() => _selectedIndex = 1);
  }

  void _scheduleFirstLoginCharacterPrompt(List<StudentModel> children) {
    if (_characterPromptScheduled || !widget.promptForCharacterOnEntry) return;

    StudentModel? targetChild;
    for (final child in children) {
      final characterId = child.characterId?.trim();
      if (characterId == null || characterId.isEmpty) {
        targetChild = child;
        break;
      }
    }
    if (targetChild == null) {
      _characterPromptScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _firstLoginCharacterPromptCompleted = true);
        _clearFirstLoginPromptFlag();
      });
      return;
    }

    final promptChild = targetChild;
    _characterPromptScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        showCharacterPicker(
          context,
          student: promptChild,
          onChanged: (_) => ref.invalidate(parentChildrenProvider),
        ).whenComplete(_handleFirstLoginCharacterPromptComplete),
      );
    });
  }

  void _handleFirstLoginCharacterPromptComplete() {
    if (!mounted) return;
    setState(() => _firstLoginCharacterPromptCompleted = true);
    _clearFirstLoginPromptFlag();
  }

  void _scheduleParentTourIfReady() {
    if (_parentTourScheduled) return;
    if (widget.promptForCharacterOnEntry &&
        !_firstLoginCharacterPromptCompleted) {
      return;
    }
    _parentTourScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startParentTour();
    });
  }

  void _startParentTour({bool force = false}) {
    unawaited(
      _tourController.start(
        definition: LumiTourDefinitions.parent,
        userId: widget.user.id,
        force: force,
        onStepChanged: _handleParentTourStep,
      ),
    );
  }

  Future<void> _handleParentTourStep(LumiTourStep step) async {
    final tabIndex = step.tabIndex;
    if (tabIndex != null && mounted && _selectedIndex != tabIndex) {
      setState(() => _selectedIndex = tabIndex);
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// Shows a one-time celebration modal when a child has newly won the weekly
  /// Top Reader award or been given a teacher's special award. Driven by the
  /// live award fields on [children]; deduped once per distinct award via
  /// [AwardCelebrationStore]. Deferred while the first-login character prompt
  /// or the guided tour is running so celebrations don't stack on onboarding.
  void _scheduleAwardCelebration(List<StudentModel> children) {
    if (_awardCelebrationInFlight) return;
    if (widget.promptForCharacterOnEntry &&
        !_firstLoginCharacterPromptCompleted) {
      return;
    }
    if (_tourController.isActive) return;

    StudentModel? target;
    String? awardKey;
    for (final child in children) {
      final key = AwardCelebrationStore.keyFor(child);
      if (key == null || _celebratedAwardKeysThisSession.contains(key)) {
        continue;
      }
      target = child;
      awardKey = key;
      break;
    }
    if (target == null || awardKey == null) return;

    final child = target;
    final key = awardKey;
    _awardCelebrationInFlight = true;
    // Mark session-seen synchronously so rapid rebuilds can't queue duplicates.
    _celebratedAwardKeysThisSession.add(key);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _awardCelebrationInFlight = false;
        return;
      }
      final alreadyCelebrated = await AwardCelebrationStore.isCelebrated(key);
      if (!mounted || _tourController.isActive) {
        _awardCelebrationInFlight = false;
        return;
      }
      if (!alreadyCelebrated) {
        await AwardCelebrationStore.markCelebrated(key);
        if (!mounted) {
          _awardCelebrationInFlight = false;
          return;
        }
        await showAwardCelebrationDialog(context, child: child);
      }
      _awardCelebrationInFlight = false;
      // Another child may also have an uncelebrated award — check again.
      if (mounted) {
        final latest = ref.read(parentChildrenProvider).value;
        if (latest != null) _scheduleAwardCelebration(latest);
      }
    });
  }

  void _clearFirstLoginPromptFlag() {
    if (!mounted || !widget.promptForCharacterOnEntry) return;

    final uri = GoRouterState.of(context).uri;
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    if (queryParameters.remove('firstParentLogin') == null) return;

    final nextUri = Uri(
      path: uri.path,
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
    context.replace(nextUri.toString());
  }

  Future<bool> _hasReadingLogToday(StudentModel student) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    try {
      final snapshot = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(student.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: student.id)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .orderBy('date', descending: true)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('[ParentHomeScreen] widget logged-state check failed: $e');
      return false;
    }
  }

  Future<List<AllocationModel>> _loadActiveAllocationsFor(
    StudentModel student,
  ) async {
    final firestore = FirebaseService.instance.firestore;
    late final List<QuerySnapshot<Map<String, dynamic>>> snapshots;
    try {
      snapshots = await Future.wait([
        firestore
            .collection('schools')
            .doc(student.schoolId)
            .collection('allocations')
            .where('studentIds', arrayContains: student.id)
            .where('isActive', isEqualTo: true)
            .get(),
        firestore
            .collection('schools')
            .doc(student.schoolId)
            .collection('allocations')
            .where('classId', isEqualTo: student.classId)
            .where('studentIds', isEqualTo: [])
            .where('isActive', isEqualTo: true)
            .get(),
      ]);
    } catch (e) {
      debugPrint('[ParentHomeScreen] widget allocation load failed: $e');
      return const [];
    }
    final now = DateTime.now();
    final seen = <String>{};
    final allocations = <AllocationModel>[];
    for (final doc in snapshots.expand((snapshot) => snapshot.docs)) {
      if (!seen.add(doc.id)) continue;
      final candidate = AllocationModel.fromFirestore(doc);
      if (candidate.startDate.isBefore(now) && candidate.endDate.isAfter(now)) {
        allocations.add(candidate);
      }
    }
    return allocations;
  }

  @override
  Widget build(BuildContext context) {
    // Defense-in-depth: this is a parent-only screen. If a non-parent (e.g. a
    // teacher whose session briefly resolved to /parent/home during the async
    // auth redirect, or an iOS widget deep link) reaches it, bounce them to
    // their own home instead of rendering the parent "no children" state —
    // guarantees a teacher never sees this screen.
    if (widget.user.role != UserRole.parent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.go(widget.user.role == UserRole.teacher
            ? '/teacher/home'
            : '/auth/admin-portal');
      });
      return const Scaffold(
        backgroundColor: LumiTokens.cream,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Keep the iOS home-screen widget in sync with the child list.
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
            // Caches the parent so lifecycle handling can clear retired widget
            // queue keys on resume from any parent screen.
            parent: widget.user,
          );
          // Clears any stale queue left by older widget builds that supported
          // live AppIntent logging.
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
            _scheduleFirstLoginCharacterPrompt(children);
            _scheduleParentTourIfReady();
            _scheduleAwardCelebration(children);
            final activeChild =
                ref.watch(activeChildProvider).value ?? children.first;
            final schoolIds = {
              for (final child in children) child.schoolId,
            };
            final quickLoggingBySchoolId = {
              for (final schoolId in schoolIds)
                schoolId: ref.watch(quickLoggingEnabledProvider(schoolId)),
            };
            // School-local day per school: the day-boundary authority for
            // occurredOn stamping, the Home "today" window and the quick-slot
            // date. schoolTodayProvider re-emits at school-local midnight so
            // Home rolls over without an app restart (§6.5).
            final timezoneBySchoolId = {
              for (final schoolId in schoolIds)
                schoolId: ref.watch(schoolTimezoneProvider(schoolId)),
            };
            final schoolTodayBySchoolId = {
              for (final entry in timezoneBySchoolId.entries)
                entry.key:
                    ref.watch(schoolTodayProvider(entry.value)).value ??
                        SchoolTime.todayFor(entry.value),
            };
            _scheduleWidgetDeepLinkHandling(children);
            return LumiTourScope(
              controller: _tourController,
              child: Scaffold(
                backgroundColor: LumiTokens.cream,
                body: Stack(
                  children: [
                    Column(
                      children: [
                        // Legacy widget undo banner. New widget taps deep-link
                        // into the normal logging flow, but this still lets old
                        // post-commit records expire or be dismissed cleanly.
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
                                child: _buildHomeView(
                                  activeChild,
                                  children,
                                  quickLoggingBySchoolId:
                                      quickLoggingBySchoolId,
                                  timezoneBySchoolId: timezoneBySchoolId,
                                  schoolTodayBySchoolId:
                                      schoolTodayBySchoolId,
                                ),
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
                                child: ParentProfileScreen(
                                  user: widget.user,
                                  onReplayTour: () =>
                                      _startParentTour(force: true),
                                ),
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
                    LumiTourOverlay(controller: _tourController),
                  ],
                ),
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
      (
        icon: Icons.settings_outlined,
        label: 'Settings',
        color: LumiTokens.green
      ),
    ];
    const targetIds = [
      'parent.nav.home',
      'parent.nav.library',
      'parent.nav.settings',
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
                    child: LumiTourTarget(
                      id: targetIds[i],
                      child: _ParentNavItem(
                        icon: navItems[i].icon,
                        label: navItems[i].label,
                        isSelected: _selectedIndex == i,
                        onTap: () => setState(() => _selectedIndex = i),
                        selectedColor: navItems[i].color,
                        unselectedColor: LumiTokens.muted,
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
          onTap: () => AddEmailForRecoveryModal.show(
              context: context, user: widget.user),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: LumiTokens.red.withValues(alpha: 0.9)),
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
    List<StudentModel> children, {
    required Map<String, bool> quickLoggingBySchoolId,
    required Map<String, String> timezoneBySchoolId,
    required Map<String, String> schoolTodayBySchoolId,
  }) {
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
                                borderRadius: BorderRadius.circular(
                                    LumiTokens.radiusPill),
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
          if (!_accountHasEmail)
            SliverToBoxAdapter(child: _buildRecoveryBanner()),

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
                  LumiTourTarget(
                    id: 'parent.readingCard',
                    child: Builder(builder: (context) {
                      final card = _ChildTodayCard(
                        student: children.first,
                        parent: widget.user,
                        quickLoggingEnabled:
                            quickLoggingBySchoolId[children.first.schoolId] ??
                                true,
                        timezone:
                            timezoneBySchoolId[children.first.schoolId] ??
                                SchoolTime.defaultTimezone,
                        onViewHistory: () => unawaited(
                          _showReadingHistoryFor(children.first),
                        ),
                      );
                      // Respect Reduce Motion (§3.6).
                      return context.motionAllowed
                          ? card.animate().fadeIn().scale()
                          : card;
                    }),
                  )
                else
                  LumiTourTarget(
                    id: 'parent.readingCard',
                    child: Builder(builder: (context) {
                      final card = _TonightMultiCard(
                        children: children,
                        parent: widget.user,
                        quickLoggingBySchoolId: quickLoggingBySchoolId,
                        timezoneBySchoolId: timezoneBySchoolId,
                        schoolTodayBySchoolId: schoolTodayBySchoolId,
                      );
                      return context.motionAllowed
                          ? card.animate().fadeIn()
                          : card;
                    }),
                  ),

                LumiGap.m,

                // One calm momentum card for the active child. Taps through to
                // the full Progress screen (stats, rhythm, achievements).
                LumiTourTarget(
                  id: 'parent.progressCard',
                  child: _MomentumCard(
                    student: selectedChild,
                  ).animate().fadeIn(delay: 100.ms),
                ),
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
              variant: LumiVariant.linking,
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
  final bool quickLoggingEnabled;
  final VoidCallback onViewHistory;

  /// School IANA timezone — day-boundary authority for occurredOn stamping.
  final String timezone;

  /// Opens the full detail wizard.
  final VoidCallback? onTap;

  const _TodayCard({
    required this.student,
    required this.parent,
    this.activeAllocations = const [],
    this.coverUrlResolver,
    required this.hasLoggedToday,
    this.todayLogs = const [],
    required this.quickLoggingEnabled,
    required this.onViewHistory,
    this.timezone = SchoolTime.defaultTimezone,
    this.onTap,
  });

  @override
  State<_TodayCard> createState() => _TodayCardState();
}

class _TodayCardState extends State<_TodayCard> {
  bool _isQuickLogging = false;

  /// The id my most recent quick log from THIS card returned — the immediate,
  /// confirmation-free undo layer targets exactly this session (§3.3/§5).
  String? _lastQuickLogId;

  StudentModel get student => widget.student;
  List<AllocationModel> get activeAllocations => widget.activeAllocations;
  bool get hasLoggedToday => widget.hasLoggedToday;
  List<ReadingLogModel> get todayLogs => widget.todayLogs;
  bool get quickLoggingEnabled => widget.quickLoggingEnabled;
  String? Function(String title)? get coverUrlResolver =>
      widget.coverUrlResolver;
  VoidCallback? get onTap => widget.onTap;

  int get _targetMinutes =>
      activeAllocations.isNotEmpty ? activeAllocations.first.targetMinutes : 20;

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

  String get _quickLogLabel => 'Quick log $_targetMinutes min';

  /// Whether a one-tap log has anything legitimate to attribute — mirrors
  /// the service's union resolution. Empty ⇒ the affordance becomes
  /// "Choose book" (a title is never fabricated).
  bool get _hasResolvableBook => _firstAssignedTitle != null;

  /// The just-created session this guardian may still undo in one tap.
  ReadingLogModel? get _undoableLog {
    final id = _lastQuickLogId;
    if (id == null) return null;
    for (final log in todayLogs) {
      if (log.id == id && log.parentId == widget.parent.id) return log;
    }
    return null;
  }

  Future<void> _handleUndoQuickLog() async {
    final log = _undoableLog;
    if (log == null) return;
    try {
      await ReadingLogService.instance.deleteOwnLog(log);
      if (!mounted) return;
      setState(() => _lastQuickLogId = null);
      announceForAccessibility(context, ParentLoggingCopy.undoDone);
      showLumiToast(
        message: ParentLoggingCopy.undoDone,
        type: LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      showLumiToast(
        message: "Couldn't undo — please try again.",
        type: LumiToastType.error,
      );
    }
  }

  /// Records a default reading log for today in a single tap (Rec 1).
  Future<void> _handleQuickLog() async {
    if (_isQuickLogging) return;
    if (!quickLoggingEnabled) {
      showLumiToast(
        message:
            'Quick log is turned off by your school. Use Log reading to add details.',
        type: LumiToastType.info,
      );
      return;
    }
    // Access gate: the quick-log write bypasses the /parent/log-reading route's
    // hasActiveAccess check, so when a school's licence lapses the parent would
    // otherwise hit an endless "Couldn't log reading" loop. Route to the gate,
    // which the router renders as AccessLockedScreen with a clear reason.
    if (!student.hasActiveAccess) {
      NavigationStateService().setTempData({
        'parent': widget.parent,
        'student': student,
        'allocations': activeAllocations,
      });
      context.push('/parent/log-reading');
      return;
    }
    setState(() => _isQuickLogging = true);
    try {
      final result = await ReadingLogService.instance.logReading(
        student: student,
        parent: widget.parent,
        allocations: activeAllocations,
        quickLog: true,
        schoolTimezone: widget.timezone,
      );
      if (!mounted) return;
      // Remember the exact session for the one-tap undo shown when the
      // parent returns from the celebration screen.
      setState(() {
        _lastQuickLogId = result.log.id;
        _isQuickLogging = false;
      });
      announceForAccessibility(
        context,
        ParentLoggingCopy.semanticsSaved(
            result.log.minutesRead, student.firstName),
      );
      context.go('/parent/reading-success', extra: {
        'student': student,
        'parent': widget.parent,
        'readingLog': result.log,
        'updatedStats': result.updatedStats,
        'savedOffline': result.savedOffline,
        'restDayApplied': result.restDayApplied,
      });
    } on QuickLoggingDisabledException {
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message:
            'Quick log is turned off by your school. Use Log reading to add details.',
        type: LumiToastType.info,
      );
    } on NoCurrentBookException {
      // No resolvable book: never fabricate a title — choose one in the
      // detailed flow instead (row-level Choose book covers the usual path).
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      NavigationStateService().setTempData({
        'parent': widget.parent,
        'student': student,
        'allocations': activeAllocations,
      });
      context.push('/parent/log-reading');
    } on QuickSlotTakenException catch (e) {
      // Someone else won the day's default session — nothing was written.
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message: ParentLoggingCopy.slotLost(e),
        type: LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message: "Couldn't log reading. Please try again.",
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: hasLoggedToday ? widget.onViewHistory : onTap,
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
                    color:
                        hasLoggedToday ? LumiTokens.tintGreen : LumiTokens.red,
                    borderRadius: LumiBorders.circular,
                  ),
                  child: Text(
                    DateFormat('EEEE, MMM d').format(DateTime.now()),
                    style: LumiType.caption.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: hasLoggedToday ? LumiTokens.ink : LumiTokens.paper,
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
            // Avatar keeps the child visible on single-child accounts, where
            // the switcher chips and multi-child rows (the only other places
            // it appears on Home) are hidden.
            Row(
              children: [
                StudentAvatar.fromStudent(student, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    hasLoggedToday
                        ? '${student.firstName} — all done!'
                        : "${student.firstName}'s reading",
                    style: LumiType.subhead,
                  ),
                ),
              ],
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
                final allBooks = activeAllocations
                    .where((a) => a.type == AllocationType.byTitle)
                    .expand(
                      (a) => a.effectiveAssignmentItemsForStudent(student.id),
                    )
                    .where((item) => item.title.trim().isNotEmpty)
                    .where((item) => seen.add(item.title.trim().toLowerCase()))
                    .map((item) => (
                          title: item.title,
                          renewed: item.metadata?['renewed'] == true,
                        ))
                    .toList();

                if (levelAllocation == null && allBooks.isEmpty) {
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
                    ...allBooks.map((book) {
                      final displayTitle =
                          IsbnAssignmentService.sanitizeDisplayTitle(
                              book.title);
                      return Padding(
                        padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                        child: LumiBookCard(
                          title: displayTitle,
                          bookType: BookType.library,
                          statusText: book.renewed ? 'Renewed' : 'Assigned',
                          coverUrl: coverUrlResolver?.call(book.title),
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
            if (hasLoggedToday) ...[
              SizedBox(
                width: double.infinity,
                child: LumiPrimaryButton(
                  onPressed: widget.onViewHistory,
                  text: 'View reading history',
                  icon: Icons.history_rounded,
                  color: LumiTokens.red,
                ),
              ),
              LumiGap.xxs,
              Center(
                child: LumiTextButton(
                  onPressed: onTap,
                  text: 'Add another session',
                  icon: Icons.add_circle_outline,
                  color: LumiTokens.red,
                ),
              ),
              // Immediate, confirmation-free undo of exactly the session this
              // guardian just created — deliberately NOT where the quick-log
              // button was, so a rapid second tap can't land on it (§3.3).
              if (_undoableLog != null)
                Center(
                  child: LumiTextButton(
                    onPressed: _handleUndoQuickLog,
                    text: ParentLoggingCopy.undoMyQuickLog,
                    icon: Icons.undo_rounded,
                    color: LumiTokens.muted,
                  ),
                ),
            ] else ...[
              LumiPrimaryButton(
                onPressed: _isQuickLogging ? null : onTap,
                isFullWidth: true,
                text: 'Log reading',
                icon: Icons.edit_note_rounded,
                color: LumiTokens.red,
              ),
              LumiGap.xxs,
              if (quickLoggingEnabled) ...[
                Center(
                  child: Semantics(
                    button: true,
                    label: _hasResolvableBook
                        ? ParentLoggingCopy.semanticsQuickLog(_targetMinutes,
                            student.firstName, _firstAssignedTitle!)
                        : '${ParentLoggingCopy.needsBookAction} '
                            'for ${student.firstName}',
                    excludeSemantics: true,
                    child: LumiTextButton(
                      onPressed: _isQuickLogging
                          ? null
                          : (_hasResolvableBook ? _handleQuickLog : onTap),
                      isLoading: _isQuickLogging,
                      // No resolvable book ⇒ the action says what it does:
                      // choose one. A title is never fabricated (§4.1).
                      text: _hasResolvableBook
                          ? _quickLogLabel
                          : ParentLoggingCopy.needsBookAction,
                      icon: _hasResolvableBook
                          ? Icons.check_circle_outline
                          : Icons.menu_book_outlined,
                      color: LumiTokens.red,
                    ),
                  ),
                ),
                if (_hasResolvableBook) ...[
                  LumiGap.xxs,
                  Center(
                    child: Text(
                      'Quick log records $_quickLogSummary',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.ink.withValues(alpha: 0.55),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
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
  final bool quickLoggingEnabled;
  final String timezone;
  final VoidCallback onViewHistory;

  const _ChildTodayCard({
    required this.student,
    required this.parent,
    required this.quickLoggingEnabled,
    this.timezone = SchoolTime.defaultTimezone,
    required this.onViewHistory,
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
              quickLoggingEnabled: widget.quickLoggingEnabled,
              timezone: widget.timezone,
              onViewHistory: widget.onViewHistory,
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
class _MomentumCard extends StatefulWidget {
  final StudentModel student;

  const _MomentumCard({required this.student});

  @override
  State<_MomentumCard> createState() => _MomentumCardState();
}

class _MomentumCardState extends State<_MomentumCard> {
  // Streams are created once (and only re-created when the student changes) so
  // parent rebuilds don't tear down and re-subscribe the Firestore listeners —
  // same pattern as _ChildTodayCardState above. Broadcast so a StreamBuilder
  // re-subscription (rebuild/reinsertion) doesn't trip "Stream has already
  // been listened to".
  late Stream<DocumentSnapshot> _studentStream;
  late Stream<QuerySnapshot> _weekLogsStream;

  StudentModel get student => widget.student;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(covariant _MomentumCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.student.id != widget.student.id ||
        oldWidget.student.schoolId != widget.student.schoolId) {
      _initStreams();
    }
  }

  void _initStreams() {
    final firestore = FirebaseService.instance.firestore;
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    _studentStream = firestore
        .collection('schools')
        .doc(student.schoolId)
        .collection('students')
        .doc(student.id)
        .snapshots()
        .asBroadcastStream();
    _weekLogsStream = firestore
        .collection('schools')
        .doc(student.schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: student.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .snapshots()
        .asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    final accent = context.sectionTheme.accent;
    final now = DateTime.now();

    return GestureDetector(
      onTap: () =>
          context.push('/parent/progress', extra: {'student': student}),
      child: LumiCard(
        child: StreamBuilder<DocumentSnapshot>(
          stream: _studentStream,
          builder: (context, studentSnap) {
            int totalNights = 0;
            int currentStreak = 0;
            if (studentSnap.hasData && studentSnap.data!.exists) {
              final stats = StudentModel.fromFirestore(studentSnap.data!).stats;
              totalNights = stats?.totalReadingDays ?? 0;
              currentStreak = stats?.currentStreak ?? 0;
            }
            final displayedStreak = currentStreak.clamp(0, totalNights);
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
                    if (displayedStreak > 0) ...[
                      Icon(
                        Icons.local_fire_department,
                        color: LumiTokens.orange.withValues(alpha: 0.85),
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$displayedStreak-night streak',
                        style:
                            LumiType.body.copyWith(fontWeight: FontWeight.w600),
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
                  stream: _weekLogsStream,
                  builder: (context, weekSnap) {
                    final completedDays = <int>{};
                    if (weekSnap.hasData) {
                      for (final doc in weekSnap.data!.docs) {
                        completedDays.add(
                            ReadingLogModel.fromFirestore(doc).date.weekday);
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
///
/// Stateful so it can own ONE whole-class allocations listener per distinct
/// classId — siblings in the same class previously each opened an identical
/// Firestore listener from their own [_TonightRow]. The latest snapshot per
/// class is passed down to the rows as plain data.
class _TonightMultiCard extends StatefulWidget {
  final List<StudentModel> children;
  final UserModel parent;
  final Map<String, bool> quickLoggingBySchoolId;
  final Map<String, String> timezoneBySchoolId;
  final Map<String, String> schoolTodayBySchoolId;

  const _TonightMultiCard({
    required this.children,
    required this.parent,
    required this.quickLoggingBySchoolId,
    required this.timezoneBySchoolId,
    required this.schoolTodayBySchoolId,
  });

  @override
  State<_TonightMultiCard> createState() => _TonightMultiCardState();
}

class _TonightMultiCardState extends State<_TonightMultiCard> {
  final Map<String, StreamSubscription<QuerySnapshot>> _classAllocSubs = {};
  final Map<String, QuerySnapshot> _classAllocSnaps = {};

  List<StudentModel> get children => widget.children;
  UserModel get parent => widget.parent;

  @override
  void initState() {
    super.initState();
    _syncClassSubscriptions();
  }

  @override
  void didUpdateWidget(covariant _TonightMultiCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClassSubscriptions();
  }

  @override
  void dispose() {
    for (final sub in _classAllocSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }

  /// One live whole-class allocations listener per distinct classId among the
  /// children; cancels listeners for classes no longer represented.
  void _syncClassSubscriptions() {
    final firestore = FirebaseService.instance.firestore;
    final schoolId = widget.parent.schoolId;
    final wanted = {
      for (final child in widget.children)
        if (child.classId.isNotEmpty) child.classId,
    };

    for (final classId in _classAllocSubs.keys.toList()) {
      if (!wanted.contains(classId)) {
        _classAllocSubs.remove(classId)?.cancel();
        _classAllocSnaps.remove(classId);
      }
    }

    for (final classId in wanted) {
      if (_classAllocSubs.containsKey(classId)) continue;
      _classAllocSubs[classId] = firestore
          .collection('schools')
          .doc(schoolId)
          .collection('allocations')
          .where('classId', isEqualTo: classId)
          .where('studentIds', isEqualTo: [])
          .where('isActive', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
            if (!mounted) return;
            setState(() => _classAllocSnaps[classId] = snapshot);
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyQuickLoggingEnabled = children.any(
      (child) => widget.quickLoggingBySchoolId[child.schoolId] ?? true,
    );

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
          // Rows render in linkedChildren order and are keyed by child id —
          // logging one child NEVER reorders or resizes a sibling's row
          // (§3.1 layout-stability invariant, locked by widget tests).
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: LumiTokens.rule),
            _TonightRow(
              key: ValueKey(children[i].id),
              student: children[i],
              parent: parent,
              quickLoggingEnabled:
                  widget.quickLoggingBySchoolId[children[i].schoolId] ?? true,
              timezone: widget.timezoneBySchoolId[children[i].schoolId] ??
                  SchoolTime.defaultTimezone,
              schoolToday:
                  widget.schoolTodayBySchoolId[children[i].schoolId] ??
                      SchoolTime.todayFor(
                          widget.timezoneBySchoolId[children[i].schoolId]),
              classAllocations: _classAllocSnaps[children[i].classId],
            ),
          ],
          LumiGap.xs,
          // Teach both gestures: the row opens the richer flow, the labelled
          // button is the one-tap shortcut.
          Row(
            children: [
              Icon(Icons.touch_app_outlined,
                  size: 14, color: LumiTokens.muted.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  anyQuickLoggingEnabled
                      ? 'Tap a name to add how it went · use the button to log fast'
                      : 'Tap a name to log reading details',
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
  final bool quickLoggingEnabled;

  /// School IANA timezone + the current school-local day ('YYYY-MM-DD') —
  /// the day-boundary authority for the row's query window, state machine
  /// and quick-slot date. schoolToday flips at school-local midnight.
  final String timezone;
  final String schoolToday;

  /// Latest whole-class allocations for this student's class, owned and
  /// deduped by [_TonightMultiCardState] (one listener per distinct class
  /// instead of one per sibling). Null until that listener's first snapshot.
  final QuerySnapshot? classAllocations;

  const _TonightRow({
    super.key,
    required this.student,
    required this.parent,
    required this.quickLoggingEnabled,
    required this.timezone,
    required this.schoolToday,
    this.classAllocations,
  });

  @override
  State<_TonightRow> createState() => _TonightRowState();
}

class _TonightRowState extends State<_TonightRow> {
  Stream<QuerySnapshot>? _todayLogsStream;
  late final Stream<QuerySnapshot> _allocationsStream;
  bool _isQuickLogging = false;

  /// The id my most recent quick log from THIS row returned — the immediate
  /// undo layer targets exactly this session. Cleared on day rollover.
  String? _lastQuickLogId;

  /// This child's queued (saved-on-this-phone) sessions and any parked
  /// quick-slot conflict, live from the outbox (§7.1/§7.2).
  StreamSubscription<List<PendingSync>>? _queueSub;
  List<ReadingLogModel> _pendingLogs = const [];
  String? _conflictLogId;
  String? _conflictWinnerUid;

  @override
  void initState() {
    super.initState();
    final firestore = FirebaseService.instance.firestore;
    final schoolId = widget.parent.schoolId;
    _initTodayStream();
    _refreshPendingFromQueue(OfflineService.instance.pendingSyncs);
    _queueSub = OfflineService.instance.queueStream
        .listen(_refreshPendingFromQueue);

    // Allocations targeting this student specifically. Whole-class
    // allocations arrive via widget.classAllocations (shared per class by
    // the parent card). Broadcast so a rebuild's re-subscribe is safe.
    _allocationsStream = firestore
        .collection('schools')
        .doc(schoolId)
        .collection('allocations')
        .where('studentIds', arrayContains: widget.student.id)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .asBroadcastStream();
  }

  void _refreshPendingFromQueue(List<PendingSync> queue) {
    if (!mounted) return;
    final mine = OfflineService.instance
        .pendingReadingLogsFor(widget.student.id)
        .where((log) =>
            (log.occurredOn ??
                SchoolTime.localDateString(log.date, widget.timezone)) ==
            widget.schoolToday)
        .toList();
    final conflicts = OfflineService.instance
        .quickSlotConflicts
        .where((it) => it.data['studentId'] == widget.student.id)
        .toList();
    setState(() {
      _pendingLogs = mine;
      _conflictLogId = conflicts.isEmpty ? null : conflicts.first.id;
      _conflictWinnerUid = conflicts.isEmpty
          ? null
          : (conflicts.first.data[quickSlotConflictKey]
              as Map?)?['byUid'] as String?;
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    super.dispose();
  }

  /// Query window = the school-local day ±1 day, membership decided
  /// client-side by `occurredOn ?? derived-day` — so an offline log made
  /// before midnight, a backdated session, or a device clock ahead of school
  /// time all land in the right day (§6.5).
  void _initTodayStream() {
    final start = SchoolTime.utcRangeForLocalDay(
      SchoolTime.shiftDays(widget.schoolToday, -1),
      widget.timezone,
    ).startInclusive;
    final end = SchoolTime.utcRangeForLocalDay(
      SchoolTime.shiftDays(widget.schoolToday, 1),
      widget.timezone,
    ).endExclusive;
    _todayLogsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.parent.schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: widget.student.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .asBroadcastStream();
  }

  @override
  void didUpdateWidget(covariant _TonightRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolToday != widget.schoolToday ||
        oldWidget.timezone != widget.timezone) {
      // School-local midnight rolled over (schoolTodayProvider) — re-derive
      // the day window and retire yesterday's immediate-undo affordance.
      setState(() {
        _lastQuickLogId = null;
        _initTodayStream();
      });
    }
  }

  List<ReadingLogModel> _todayFrom(AsyncSnapshot<QuerySnapshot> snapshot) {
    if (!snapshot.hasData) return const [];
    return snapshot.data!.docs
        .map((doc) => ReadingLogModel.fromFirestore(doc))
        .where((log) =>
            (log.occurredOn ??
                SchoolTime.localDateString(log.date, widget.timezone)) ==
            widget.schoolToday)
        .toList();
  }

  /// Union of the child's effective assigned titles (D3), deduped/sanitized —
  /// the same resolution the service applies, so the row's preview and the
  /// persisted payload can't drift apart.
  List<String> _resolvedTitles(List<AllocationModel> allocations) {
    final seen = <String>{};
    final titles = <String>[];
    for (final allocation in allocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(widget.student.id)) {
        final title = item.title.trim();
        if (title.isEmpty) continue;
        if (!seen.add(title.toLowerCase())) continue;
        titles.add(IsbnAssignmentService.sanitizeDisplayTitle(title));
      }
    }
    return titles;
  }

  List<AllocationModel> _activeFrom(AsyncSnapshot<QuerySnapshot> snapshot) {
    final result = <AllocationModel>[];
    final now = DateTime.now();
    final seen = <String>{};
    final docs = [
      ...?snapshot.data?.docs,
      ...?widget.classAllocations?.docs,
    ];
    for (final doc in docs) {
      if (!seen.add(doc.id)) continue;
      final candidate = AllocationModel.fromFirestore(doc);
      if (candidate.startDate.isBefore(now) && candidate.endDate.isAfter(now)) {
        result.add(candidate);
      }
    }
    return result;
  }

  Future<void> _quickLog(List<AllocationModel> allocations) async {
    if (_isQuickLogging) return;
    // Access gate — route to the log-reading gate (→ AccessLockedScreen) rather
    // than attempting a write the licence no longer permits (endless retry).
    if (!widget.student.hasActiveAccess) {
      _openDetail(allocations);
      return;
    }
    // Lock synchronously at the moment of the tap (§3.3 step 1).
    setState(() => _isQuickLogging = true);
    try {
      final result = await ReadingLogService.instance.logReading(
        student: widget.student,
        parent: widget.parent,
        allocations: allocations,
        quickLog: true,
        schoolTimezone: widget.timezone,
      );
      if (!mounted) return;
      setState(() {
        _lastQuickLogId = result.log.id;
        _isQuickLogging = false;
      });
      announceForAccessibility(
        context,
        ParentLoggingCopy.semanticsSaved(
            result.log.minutesRead, widget.student.firstName),
      );
      context.go('/parent/reading-success', extra: {
        'student': widget.student,
        'parent': widget.parent,
        'readingLog': result.log,
        'updatedStats': result.updatedStats,
        'savedOffline': result.savedOffline,
        'restDayApplied': result.restDayApplied,
      });
    } on QuickLoggingDisabledException {
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message:
            'Quick log is turned off by your school. Tap the name to add details.',
        type: LumiToastType.info,
      );
    } on NoCurrentBookException {
      // Defensive — the row shows "Choose book" before this can fire.
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      _openDetail(allocations);
    } on QuickSlotTakenException catch (e) {
      // Someone else won the day's default session — nothing was written.
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message: ParentLoggingCopy.slotLost(e),
        type: LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isQuickLogging = false);
      showLumiToast(
        message: "Couldn't log reading. Please try again.",
        type: LumiToastType.error,
      );
    }
  }

  Future<void> _undoQuickLog(ReadingLogModel log) async {
    try {
      await ReadingLogService.instance.deleteOwnLog(log);
      if (!mounted) return;
      setState(() => _lastQuickLogId = null);
      announceForAccessibility(context, ParentLoggingCopy.undoDone);
      showLumiToast(
        message: ParentLoggingCopy.undoDone,
        type: LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      showLumiToast(
        message: "Couldn't undo — please try again.",
        type: LumiToastType.error,
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
        final todayLogs = _todayFrom(logSnapshot);

        return StreamBuilder<QuerySnapshot>(
          stream: _allocationsStream,
          builder: (context, allocationSnapshot) {
            final allocations = _activeFrom(allocationSnapshot);
            BookCoverCacheService.instance.primeFromAllocations(
              allocations,
              FirebaseService.instance.firestore,
            );
            final titles = _resolvedTitles(allocations);
            final usualMinutes = allocations.isNotEmpty
                ? allocations.first.targetMinutes
                : 20;

            final state = deriveChildLogRowState(
              student: widget.student,
              todayLogs: todayLogs,
              resolvedBookTitles: titles,
              usualMinutes: usualMinutes,
              quickLoggingEnabled: widget.quickLoggingEnabled,
              submitting: _isQuickLogging,
              myUid: widget.parent.id,
              justCreatedLogId: _lastQuickLogId,
              pendingLogs: _pendingLogs,
              conflictLogId: _conflictLogId,
            );

            final undoable = state is RowJustCreatedByMe ? state.log : null;

            return ChildLogRow(
              key: ValueKey(widget.student.id),
              student: widget.student,
              state: state,
              onOpenDetail: () {
                if (!_isQuickLogging) _openDetail(allocations);
              },
              onQuickLog: () => _quickLog(allocations),
              onChooseBook: () => _openDetail(allocations),
              onUndo:
                  undoable == null ? null : () => _undoQuickLog(undoable),
              // Review routes by state: a parked conflict gets the §7.2
              // prompt, a pending session its Edit/Cancel sheet, and
              // everything else Tonight's sessions — the durable
              // per-session recovery layer (§5.1).
              onReview: () {
                if (state is RowConflict) {
                  showQuickSlotConflictDialog(
                    context,
                    student: widget.student,
                    pendingLogId: state.pendingLogId,
                    winnerName: _conflictWinnerUid == widget.parent.id
                        ? 'You (another device)'
                        : null,
                  );
                } else if (state is RowOfflinePending) {
                  showPendingSessionSheet(
                    context,
                    student: widget.student,
                    pending: state.pending,
                  );
                } else {
                  showTodaySessionsSheet(
                    context,
                    student: widget.student,
                    myUid: widget.parent.id,
                    timezone: widget.timezone,
                    schoolToday: widget.schoolToday,
                    onAddAnotherSession: () => _openDetail(allocations),
                  );
                }
              },
              dateMismatchNote: SchoolTime.deviceDayDiffers(widget.timezone)
                  ? ParentLoggingCopy.dateMismatchNote(
                      DateFormat('EEE d MMM').format(
                          DateTime.parse('${widget.schoolToday}T12:00:00')))
                  : null,
            );
          },
        );
      },
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
              child:
                  Icon(Icons.close_rounded, size: 18, color: LumiTokens.muted),
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
