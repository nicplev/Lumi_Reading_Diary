import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/liquid_glass_theme.dart';
import '../../core/widgets/glass/glass_widgets.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';
import 'log_reading_screen.dart';
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
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LiquidGlassTheme.backgroundGradient,
          ),
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LiquidGlassTheme.backgroundGradient,
          ),
          child: _buildNoChildrenView(),
        ),
      );
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LiquidGlassTheme.backgroundGradient,
        ),
        child: IndexedStack(
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
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.gray,
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.darkGray,
                          fontWeight: FontWeight.bold,
                        ),
                  )
                else
                  Text(
                    selectedChild.firstName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.darkGray,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: AppColors.darkGray,
                onPressed: () {
                  // Navigate to notifications
                },
              ),
            ],
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(16),
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
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => LogReadingScreen(
                                        student: selectedChild,
                                        parent: widget.user,
                                        allocation: allocation,
                                      ),
                                    ),
                                  );
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

                const SizedBox(height: 20),

                // Weekly Progress
                _WeeklyProgressCard(
                  studentId: selectedChild.id,
                  schoolId: widget.user.schoolId!,
                ).animate().fadeIn(delay: 200.ms),

                const SizedBox(height: 20),

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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const LumiMascot(
              mood: LumiMood.thinking,
              size: 150,
            ),
            const SizedBox(height: 24),
            Text(
              'No Children Linked',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGray,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Please ask your teacher for an invite code to link your children.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.gray,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to enter invite code screen
              },
              icon: const Icon(Icons.qr_code),
              label: const Text('Enter Invite Code'),
            ),
          ],
        ),
      ),
    );
  }

  Stream<StudentStats?> _getStudentStats(String studentId) {
    return _firebaseService.firestore
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
    return AnimatedGlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: hasLoggedToday
                      ? LiquidGlassTheme.successGradient
                      : LiquidGlassTheme.coolGradient,
                  borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusCapsule),
                  boxShadow: hasLoggedToday
                      ? LiquidGlassTheme.glowShadow(color: AppColors.secondaryGreen)
                      : LiquidGlassTheme.glowShadow(color: AppColors.primaryBlue),
                ),
                child: Text(
                  DateFormat('EEEE, MMM d').format(DateTime.now()),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const Spacer(),
              if (hasLoggedToday)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: LiquidGlassTheme.glowShadow(
                      color: AppColors.secondaryGreen,
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.secondaryGreen,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
          Text(
            hasLoggedToday ? 'Reading Complete!' : "Today's Reading",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGray,
                ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingSm),
          if (allocation != null) ...[
            _buildRequirement(
              context,
              Icons.timer_outlined,
              '${allocation!.targetMinutes} minutes',
            ),
            const SizedBox(height: 8),
            if (allocation!.type == AllocationType.byLevel)
              _buildRequirement(
                context,
                Icons.book_outlined,
                'Level ${allocation!.levelStart}${allocation!.levelEnd != null ? ' - ${allocation!.levelEnd}' : ''} books',
              ),
            if (allocation!.type == AllocationType.byTitle &&
                allocation!.bookTitles != null)
              ...allocation!.bookTitles!.map((title) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
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
            const SizedBox(height: 8),
            _buildRequirement(
              context,
              Icons.book_outlined,
              'Any reading material',
            ),
          ],
          if (!hasLoggedToday) ...[
            const SizedBox(height: LiquidGlassTheme.spacingLg),
            GlassButton(
              text: 'Tap to Mark as Done',
              onPressed: onTap,
              isPrimary: true,
              icon: Icons.check_circle_outline,
              gradient: LiquidGlassTheme.parentGradient,
              width: double.infinity,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequirement(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: AppColors.gray,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.darkGray,
                ),
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

    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Week',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGray,
                ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
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
                  snapshot.data!.docs.map((doc) =>
                      ReadingLogModel.fromFirestore(doc)),
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
        gradient: isCompleted ? LiquidGlassTheme.successGradient : null,
        color: !isCompleted
            ? (isToday
                ? AppColors.primaryBlue.withValues(alpha: 0.2)
                : AppColors.lightGray)
            : null,
        shape: BoxShape.circle,
        border: isToday
            ? Border.all(color: AppColors.primaryBlue, width: 2)
            : null,
        boxShadow: isCompleted
            ? LiquidGlassTheme.glowShadow(
                color: AppColors.secondaryGreen,
                blurRadius: 8,
                spreadRadius: 0,
              )
            : null,
      ),
      child: Center(
        child: Text(
          day,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: isCompleted ? AppColors.white : AppColors.darkGray,
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
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Row(
        children: [
          Expanded(
            child: GlassMiniStat(
              icon: Icons.local_fire_department,
              color: AppColors.secondaryOrange,
              value: currentStreak.toString(),
              label: 'Current Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.lightGray.withValues(alpha: 0.2),
                  AppColors.lightGray,
                  AppColors.lightGray.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          Expanded(
            child: GlassMiniStat(
              icon: Icons.emoji_events,
              color: AppColors.gold,
              value: longestStreak.toString(),
              label: 'Best Streak',
            ),
          ),
          Container(
            width: 1,
            height: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.lightGray.withValues(alpha: 0.2),
                  AppColors.lightGray,
                  AppColors.lightGray.withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          Expanded(
            child: GlassMiniStat(
              icon: Icons.timer,
              color: AppColors.primaryBlue,
              value: '${totalMinutes ~/ 60}h',
              label: 'Total Time',
            ),
          ),
        ],
      ),
    );
  }
}