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
import '../../services/book_cover_cache_service.dart';
import '../../services/firebase_service.dart';
import '../../services/widget_data_service.dart';
import '../../services/isbn_assignment_service.dart';
import '../../services/staff_notification_service.dart';
import 'reading_history_screen.dart';
import 'parent_profile_screen.dart';

class ParentHomeScreen extends ConsumerStatefulWidget {
  final UserModel user;

  const ParentHomeScreen({
    super.key,
    required this.user,
  });

  @override
  ConsumerState<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends ConsumerState<ParentHomeScreen> {
  int _selectedIndex = 0;
  String? _selectedChildId;
  List<StudentModel> _children = [];
  bool _isLoading = true;

  void _onCoversUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    BookCoverCacheService.instance.addListener(_onCoversUpdated);
    _loadChildren();
  }

  @override
  void dispose() {
    BookCoverCacheService.instance.removeListener(_onCoversUpdated);
    super.dispose();
  }

  Future<void> _loadChildren() async {
    try {
      final firebaseService = ref.read(firebaseServiceProvider);
      if (widget.user.linkedChildren.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final List<StudentModel> children = [];
      for (String childId in widget.user.linkedChildren) {
        final doc = await firebaseService.firestore
            .collection('schools')
            .doc(widget.user.schoolId)
            .collection('students')
            .doc(childId)
            .get();

        if (doc.exists) {
          children.add(StudentModel.fromFirestore(doc));
        }
      }

      setState(() {
        _children = children;
        if (children.isNotEmpty) {
          _selectedChildId = children.first.id;
        }
        _isLoading = false;
      });

      // Refresh widget data whenever the parent's children list is (re)loaded.
      // Pass empty logs map — loggedToday is inferred from stats.lastReadingDate.
      if (children.isNotEmpty) {
        WidgetDataService.instance.updateFromChildren(
          children: children,
          selectedChildId: children.first.id,
          todaysLogs: {},
        );
      }
    } catch (e) {
      debugPrint('Error loading children: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Combines two Firestore query streams into a single stream of both results.
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
          if (latest2 != null) {
            controller.add([latest1!, latest2!]);
          }
        });
        sub2 = stream2.listen((snapshot) {
          latest2 = snapshot;
          if (latest1 != null) {
            controller.add([latest1!, latest2!]);
          }
        });
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.offWhite,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.rosePink,
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        body: _buildNoChildrenView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildHomeView(),
          ReadingHistoryScreen(
            studentId: _selectedChildId!,
            parentId: widget.user.id,
            schoolId: widget.user.schoolId!,
          ),
          ParentProfileScreen(user: widget.user),
        ],
      ),
      bottomNavigationBar: Container(
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
            selectedLabelStyle:
                LumiTextStyles.caption(color: AppColors.rosePink)
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
      ),
    );
  }

  Widget _buildHomeView() {
    final selectedChild = _children.firstWhere(
      (child) => child.id == _selectedChildId,
      orElse: () => _children.first,
    );
    final firebaseService = ref.read(firebaseServiceProvider);

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
                if (_children.length > 1)
                  DropdownButton<String>(
                    value: _selectedChildId,
                    items: _children.map((child) {
                      return DropdownMenuItem(
                        value: child.id,
                        child: Text(child.firstName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedChildId = value;
                      });
                    },
                    underline: const SizedBox(),
                    style: LumiTextStyles.h2(color: AppColors.charcoal),
                  )
                else
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
                      LumiIconButton(
                        icon: Icons.notifications_outlined,
                        onPressed: () {
                          context.push(
                            '/parent/notifications',
                            extra: widget.user,
                          );
                        },
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

          // Content
          SliverPadding(
            padding: LumiPadding.allS,
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Today's Reading Card
                StreamBuilder<QuerySnapshot>(
                  stream: () {
                    final now = DateTime.now();
                    final startOfDay = DateTime(now.year, now.month, now.day);
                    return firebaseService.firestore
                        .collection('schools')
                        .doc(widget.user.schoolId)
                        .collection('readingLogs')
                        .where('studentId', isEqualTo: selectedChild.id)
                        .where('date',
                            isGreaterThanOrEqualTo:
                                Timestamp.fromDate(startOfDay))
                        .orderBy('date', descending: true)
                        .snapshots();
                  }(),
                  builder: (context, logSnapshot) {
                    final todayLogs = logSnapshot.hasData
                        ? logSnapshot.data!.docs
                            .map((doc) => ReadingLogModel.fromFirestore(doc))
                            .toList()
                        : <ReadingLogModel>[];
                    final hasLoggedToday = todayLogs.isNotEmpty;

                    // Query 1: Allocations specifically for this student
                    final studentAllocationsStream = firebaseService.firestore
                        .collection('schools')
                        .doc(widget.user.schoolId!)
                        .collection('allocations')
                        .where('studentIds', arrayContains: selectedChild.id)
                        .where('isActive', isEqualTo: true)
                        .snapshots();

                    // Query 2: Whole-class allocations (studentIds is empty)
                    final classAllocationsStream = firebaseService.firestore
                        .collection('schools')
                        .doc(widget.user.schoolId!)
                        .collection('allocations')
                        .where('classId', isEqualTo: selectedChild.classId)
                        .where('studentIds', isEqualTo: [])
                        .where('isActive', isEqualTo: true)
                        .snapshots();

                    return StreamBuilder<List<QuerySnapshot>>(
                      stream: _combineStreams(
                        studentAllocationsStream,
                        classAllocationsStream,
                      ),
                      builder: (context, allocationSnapshot) {
                        final activeAllocations = <AllocationModel>[];
                        if (allocationSnapshot.hasData) {
                          final now = DateTime.now();
                          final seen = <String>{};
                          final allDocs = allocationSnapshot.data!
                              .expand((qs) => qs.docs)
                              .toList();
                          for (final doc in allDocs) {
                            if (seen.contains(doc.id)) continue;
                            seen.add(doc.id);
                            final candidate =
                                AllocationModel.fromFirestore(doc);
                            if (candidate.startDate.isBefore(now) &&
                                candidate.endDate.isAfter(now)) {
                              activeAllocations.add(candidate);
                            }
                          }
                        }
                        BookCoverCacheService.instance.primeFromAllocations(
                          activeAllocations,
                          ref.read(firebaseServiceProvider).firestore,
                        );

                        return _TodayCard(
                          student: selectedChild,
                          activeAllocations: activeAllocations,
                          coverUrlResolver:
                              BookCoverCacheService.instance.resolveCoverUrl,
                          hasLoggedToday: hasLoggedToday,
                          todayLogs: todayLogs,
                          onTap: () async {
                            // Store data in navigation service
                            NavigationStateService().setTempData({
                              'parent': widget.user,
                              'student': selectedChild,
                              'allocations': activeAllocations,
                            });

                            final result =
                                await context.push('/parent/log-reading');
                            if (result == true) {
                              // Refresh after logging
                              setState(() {});
                            }
                          },
                        ).animate().fadeIn().scale();
                      },
                    );
                  },
                ),

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
              onPressed: () {
                // Navigate to enter invite code screen
              },
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

        final result = AchievementTemplates.nearestUnearned(
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

class _TodayCard extends StatelessWidget {
  final StudentModel student;
  final List<AllocationModel> activeAllocations;
  final String? Function(String title)? coverUrlResolver;
  final bool hasLoggedToday;
  final List<ReadingLogModel> todayLogs;
  final VoidCallback? onTap;

  const _TodayCard({
    required this.student,
    this.activeAllocations = const [],
    this.coverUrlResolver,
    required this.hasLoggedToday,
    this.todayLogs = const [],
    this.onTap,
  });

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
                    color: hasLoggedToday
                        ? AppColors.mintGreen
                        : AppColors.rosePink,
                    borderRadius: LumiBorders.circular,
                  ),
                  child: Text(
                    DateFormat('EEEE, MMM d').format(DateTime.now()),
                    style: LumiTextStyles.label(
                      color: AppColors.white,
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
              hasLoggedToday ? 'Reading Complete!' : "Today's Reading",
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
            SizedBox(
              width: double.infinity,
              child: LumiPrimaryButton(
                onPressed: onTap,
                text: hasLoggedToday
                    ? 'Log Another Session'
                    : 'Tap to Mark as Done',
                icon: hasLoggedToday
                    ? Icons.add_circle_outline
                    : Icons.check_circle_outline,
              ),
            ),
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
