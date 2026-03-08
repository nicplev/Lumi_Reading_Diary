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
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadChildren();
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
    } catch (e) {
      debugPrint('Error loading children: $e');
      setState(() {
        _isLoading = false;
      });
    }
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
                icon: Icon(Icons.history_outlined),
                activeIcon: Icon(Icons.history),
                label: 'History',
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
              LumiIconButton(
                icon: Icons.notifications_outlined,
                onPressed: () {
                  // Navigate to notifications
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
                  stream: firebaseService.firestore
                      .collection('schools')
                      .doc(widget.user.schoolId)
                      .collection('readingLogs')
                      .where('studentId', isEqualTo: selectedChild.id)
                      .where('date',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(
                            DateTime.now().subtract(const Duration(hours: 24)),
                          ))
                      .limit(1)
                      .snapshots(),
                  builder: (context, logSnapshot) {
                    final hasLoggedToday = logSnapshot.hasData &&
                        logSnapshot.data!.docs.isNotEmpty;

                    return StreamBuilder<QuerySnapshot>(
                      stream: firebaseService.firestore
                          .collection('schools')
                          .doc(widget.user.schoolId!)
                          .collection('allocations')
                          .where('studentIds', arrayContains: selectedChild.id)
                          .where('startDate',
                              isLessThanOrEqualTo: Timestamp.now())
                          .where('endDate',
                              isGreaterThanOrEqualTo: Timestamp.now())
                          .where('isActive', isEqualTo: true)
                          .snapshots(),
                      builder: (context, allocationSnapshot) {
                        AllocationModel? allocation;
                        if (allocationSnapshot.hasData &&
                            allocationSnapshot.data!.docs.isNotEmpty) {
                          allocation = AllocationModel.fromFirestore(
                            allocationSnapshot.data!.docs.first,
                          );
                        }

                        return _TodayCard(
                          student: selectedChild,
                          allocation: allocation,
                          hasLoggedToday: hasLoggedToday,
                          onTap: hasLoggedToday
                              ? null
                              : () async {
                                  // Store data in navigation service
                                  NavigationStateService().setTempData({
                                    'parent': widget.user,
                                    'student': selectedChild,
                                    'allocation': allocation,
                                  });
                                  debugPrint('DEBUG: Setting temp data - parent: ${widget.user.id}, student: ${selectedChild.id}');

                                  final result = await context.push('/parent/log-reading');
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
              mood: LumiMood.thinking,
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


class _TodayCard extends StatelessWidget {
  final StudentModel student;
  final AllocationModel? allocation;
  final bool hasLoggedToday;
  final VoidCallback? onTap;

  const _TodayCard({
    required this.student,
    this.allocation,
    required this.hasLoggedToday,
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
            if (allocation != null) ...[
              _buildRequirement(
                context,
                Icons.timer_outlined,
                '${allocation!.targetMinutes} minutes',
              ),
              LumiGap.xs,
              if (allocation!.type == AllocationType.byLevel) ...[
                Text(
                  "Tonight's Books",
                  style: LumiTextStyles.bodyMedium(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                LumiGap.xs,
                LumiBookCard(
                  title: 'Level ${allocation!.levelStart}${allocation!.levelEnd != null ? ' - ${allocation!.levelEnd}' : ''}',
                  bookType: BookType.decodable,
                  statusText: 'Assigned',
                ),
              ],
              if (allocation!.type == AllocationType.byTitle &&
                  allocation!.bookTitles != null) ...[
                Text(
                  "Tonight's Books",
                  style: LumiTextStyles.bodyMedium(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                LumiGap.xs,
                ...allocation!.bookTitles!.map((title) => Padding(
                      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                      child: LumiBookCard(
                        title: title,
                        statusText: 'Assigned',
                      ),
                    )),
              ],
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
            if (!hasLoggedToday) ...[
              LumiGap.m,
              SizedBox(
                width: double.infinity,
                child: LumiPrimaryButton(
                  onPressed: onTap,
                  text: 'Tap to Mark as Done',
                  icon: Icons.check_circle_outline,
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
                  final student = StudentModel.fromFirestore(studentSnapshot.data!);
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
