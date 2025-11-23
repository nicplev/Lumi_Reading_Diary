import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../core/services/navigation_state_service.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';
import 'reading_history_screen.dart';
import 'parent_profile_screen.dart';

class ParentHomeScreen extends StatefulWidget {
  final UserModel user;

  const ParentHomeScreen({
    super.key,
    required this.user,
  });

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
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
      if (widget.user.linkedChildren.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final List<StudentModel> children = [];
      for (String childId in widget.user.linkedChildren) {
        final doc = await _firebaseService.firestore
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.rosePink,
        unselectedItemColor: AppColors.charcoal.withValues(alpha: 0.6),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Today',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHomeView() {
    final selectedChild = _children.firstWhere(
      (child) => child.id == _selectedChildId,
      orElse: () => _children.first,
    );

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
                  stream: _firebaseService.firestore
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
                      stream: _firebaseService.firestore
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

                // Weekly Progress
                _WeeklyProgressCard(
                  studentId: selectedChild.id,
                  schoolId: widget.user.schoolId!,
                ).animate().fadeIn(delay: 200.ms),

                LumiGap.m,

                // Reading Streak
                StreamBuilder<StudentStats?>(
                  stream: _getStudentStats(selectedChild.id),
                  builder: (context, snapshot) {
                    final stats = snapshot.data;
                    return _StreakCard(
                      currentStreak: stats?.currentStreak ?? 0,
                      longestStreak: stats?.longestStreak ?? 0,
                      totalMinutes: stats?.totalMinutesRead ?? 0,
                    ).animate().fadeIn(delay: 400.ms);
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
    return _firebaseService.firestore
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
              if (allocation!.type == AllocationType.byLevel)
                _buildRequirement(
                  context,
                  Icons.book_outlined,
                  'Level ${allocation!.levelStart}${allocation!.levelEnd != null ? ' - ${allocation!.levelEnd}' : ''} books',
                ),
              if (allocation!.type == AllocationType.byTitle &&
                  allocation!.bookTitles != null)
                ...allocation!.bookTitles!.map((title) => Padding(
                      padding: EdgeInsets.only(bottom: LumiSpacing.xxs),
                      child: _buildRequirement(
                        context,
                        Icons.book_outlined,
                        title,
                      ),
                    )),
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

class _WeeklyProgressCard extends StatelessWidget {
  final String studentId;
  final String schoolId;

  const _WeeklyProgressCard({
    required this.studentId,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );

    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Week',
            style: LumiTextStyles.h2(color: AppColors.charcoal),
          ),
          LumiGap.m,
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.firestore
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

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (index) {
                  final date = startOfWeek.add(Duration(days: index));
                  final hasLog = logs.any((log) =>
                      log.date.year == date.year &&
                      log.date.month == date.month &&
                      log.date.day == date.day);

                  final dayStr = DateFormat('E').format(date);
                  return _DayIndicator(
                    day: dayStr.isNotEmpty ? dayStr.substring(0, 1) : '?',
                    isCompleted: hasLog,
                    isToday: DateUtils.isSameDay(date, DateTime.now()),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayIndicator extends StatelessWidget {
  final String day;
  final bool isCompleted;
  final bool isToday;

  const _DayIndicator({
    required this.day,
    required this.isCompleted,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isCompleted
            ? AppColors.mintGreen
            : (isToday
                ? AppColors.rosePink.withValues(alpha: 0.2)
                : AppColors.skyBlue),
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: AppColors.rosePink, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          day,
          style: LumiTextStyles.label(
            color: isCompleted ? AppColors.white : AppColors.charcoal,
          ).copyWith(
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;
  final int totalMinutes;

  const _StreakCard({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalMinutes,
  });

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      child: Row(
        children: [
          Expanded(
            child: _buildMiniStat(
              icon: Icons.local_fire_department,
              color: AppColors.warmOrange,
              value: currentStreak.toString(),
              label: 'Current Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: AppColors.skyBlue,
          ),
          Expanded(
            child: _buildMiniStat(
              icon: Icons.emoji_events,
              color: AppColors.gold,
              value: longestStreak.toString(),
              label: 'Best Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: AppColors.skyBlue,
          ),
          Expanded(
            child: _buildMiniStat(
              icon: Icons.timer,
              color: AppColors.rosePink,
              value: '${totalMinutes ~/ 60}h',
              label: 'Total Time',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 32,
        ),
        LumiGap.xs,
        Text(
          value,
          style: LumiTextStyles.h2(color: AppColors.charcoal),
        ),
        LumiGap.xxs,
        Text(
          label,
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
