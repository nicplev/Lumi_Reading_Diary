import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/minimal_theme.dart';
import '../../core/widgets/minimal/minimal_widgets.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';
import 'log_reading_screen.dart';
import 'reading_history_screen.dart';
import 'parent_profile_screen.dart';

class ParentHomeScreenMinimal extends StatefulWidget {
  final UserModel user;

  const ParentHomeScreenMinimal({
    super.key,
    required this.user,
  });

  @override
  State<ParentHomeScreenMinimal> createState() => _ParentHomeScreenMinimalState();
}

class _ParentHomeScreenMinimalState extends State<ParentHomeScreenMinimal> {
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
        backgroundColor: MinimalTheme.cream,
        body: const Center(
          child: CircularProgressIndicator(
            color: MinimalTheme.primaryPurple,
          ),
        ),
      );
    }

    if (_children.isEmpty) {
      return Scaffold(
        backgroundColor: MinimalTheme.cream,
        body: _buildNoChildrenView(),
      );
    }

    return Scaffold(
      backgroundColor: MinimalTheme.cream,
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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: MinimalTheme.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MinimalTheme.spaceM,
            vertical: MinimalTheme.spaceS,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, 'Today', 0),
              _buildNavItem(Icons.history, 'History', 1),
              _buildNavItem(Icons.person, 'Profile', 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isActive = _selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? MinimalTheme.primaryPurple.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MinimalTheme.radiusPill),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? MinimalTheme.primaryPurple
                  : MinimalTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive
                    ? MinimalTheme.primaryPurple
                    : MinimalTheme.textSecondary,
              ),
            ),
          ],
        ),
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
          // App Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(MinimalTheme.spaceM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: MinimalTheme.purpleGradient,
                          shape: BoxShape.circle,
                          boxShadow: MinimalTheme.softShadow(),
                        ),
                        child: const Icon(
                          Icons.family_restroom,
                          color: MinimalTheme.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: MinimalTheme.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lumi Reading',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              'Hello ${widget.user.fullName.split(' ').first}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: MinimalTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconPillButton(
                        icon: Icons.notifications_outlined,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: MinimalTheme.spaceXL),

                  // Child Selector
                  if (_children.length > 1) ...[
                    PillTabBar(
                      tabs: _children.map((c) => c.firstName).toList(),
                      selectedIndex: _children
                          .indexWhere((c) => c.id == _selectedChildId),
                      onTabSelected: (index) {
                        setState(() {
                          _selectedChildId = _children[index].id;
                        });
                      },
                    ),
                    const SizedBox(height: MinimalTheme.spaceL),
                  ],

                  // Title
                  Text(
                    'Your Reading\nJourney',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(MinimalTheme.spaceM),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Today's Reading Card
                _buildTodayCard(selectedChild),
                const SizedBox(height: MinimalTheme.spaceL),

                // This Week
                _buildWeekCard(selectedChild),
                const SizedBox(height: MinimalTheme.spaceL),

                // Streak Stats
                _buildStreakCard(selectedChild),
                const SizedBox(height: MinimalTheme.spaceL),

                // Recent Achievements
                _buildAchievementsSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayCard(StudentModel student) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: student.id)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date',
              isLessThan: Timestamp.fromDate(startOfDay.add(const Duration(days: 1))))
          .snapshots(),
      builder: (context, snapshot) {
        final hasLoggedToday = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return StreamBuilder<DocumentSnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.user.schoolId)
              .collection('allocations')
              .doc(student.classId)
              .snapshots(),
          builder: (context, allocationSnapshot) {
            AllocationModel? allocation;
            if (allocationSnapshot.hasData && allocationSnapshot.data!.exists) {
              allocation = AllocationModel.fromFirestore(allocationSnapshot.data!);
            }

            return AnimatedRoundedCard(
              onTap: hasLoggedToday
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => LogReadingScreen(
                            student: student,
                            parent: widget.user,
                            allocation: allocation,
                          ),
                        ),
                      );
                    },
              padding: const EdgeInsets.all(MinimalTheme.spaceL),
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
                              ? MinimalTheme.successGradient
                              : MinimalTheme.purpleGradient,
                          borderRadius:
                              BorderRadius.circular(MinimalTheme.radiusPill),
                          boxShadow: MinimalTheme.softShadow(),
                        ),
                        child: Text(
                          DateFormat('EEEE, MMM d').format(DateTime.now()),
                          style: const TextStyle(
                            color: MinimalTheme.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (hasLoggedToday)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: MinimalTheme.green,
                            size: 32,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: MinimalTheme.spaceM),
                  Text(
                    hasLoggedToday ? 'Reading Complete!' : "Today's Reading",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: MinimalTheme.textPrimary,
                        ),
                  ),
                  const SizedBox(height: MinimalTheme.spaceM),
                  _buildRequirement(
                    Icons.timer_outlined,
                    allocation != null
                        ? '${allocation.targetMinutes} minutes'
                        : '20 minutes',
                  ),
                  const SizedBox(height: 8),
                  _buildRequirement(
                    Icons.book_outlined,
                    allocation != null && allocation.type == AllocationType.byLevel
                        ? 'Level ${allocation.levelStart}${allocation.levelEnd != null ? ' - ${allocation.levelEnd}' : ''} books'
                        : 'Any reading material',
                  ),
                  if (!hasLoggedToday) ...[
                    const SizedBox(height: MinimalTheme.spaceL),
                    PillButton(
                      text: 'Tap to Mark as Done',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LogReadingScreen(
                              student: student,
                              parent: widget.user,
                              allocation: allocation,
                            ),
                          ),
                        );
                      },
                      icon: Icons.check_circle_outline,
                      backgroundColor: MinimalTheme.primaryPurple,
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequirement(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: MinimalTheme.primaryPurple,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              color: MinimalTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekCard(StudentModel student) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );

    return RoundedCard(
      padding: const EdgeInsets.all(MinimalTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Week',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: MinimalTheme.textPrimary,
                ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          StreamBuilder<QuerySnapshot>(
            stream: _firebaseService.firestore
                .collection('schools')
                .doc(widget.user.schoolId)
                .collection('readingLogs')
                .where('studentId', isEqualTo: student.id)
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

              final completedDates =
                  logs.map((log) => log.date).toList();

              return WeekStreakView(
                startOfWeek: startOfWeek,
                completedDates: completedDates,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStreakCard(StudentModel student) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: student.id)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        int currentStreak = 0;
        int longestStreak = 0;
        int totalMinutes = 0;

        if (snapshot.hasData) {
          final logs = snapshot.data!.docs
              .map((doc) => ReadingLogModel.fromFirestore(doc))
              .toList();

          totalMinutes =
              logs.fold<int>(0, (total, log) => total + log.minutesRead);

          // Calculate streaks
          if (logs.isNotEmpty) {
            var tempStreak = 1;
            var maxStreak = 1;
            var prevDate = logs.first.date;

            for (var i = 1; i < logs.length; i++) {
              final diff = prevDate.difference(logs[i].date).inDays;
              if (diff == 1) {
                tempStreak++;
                maxStreak = tempStreak > maxStreak ? tempStreak : maxStreak;
              } else if (diff > 1) {
                tempStreak = 1;
              }
              prevDate = logs[i].date;
            }

            currentStreak = tempStreak;
            longestStreak = maxStreak;
          }
        }

        return StreakIndicator(
          currentStreak: currentStreak,
          longestStreak: longestStreak,
          totalMinutes: totalMinutes,
        );
      },
    );
  }

  Widget _buildAchievementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Achievements',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textPrimary,
              ),
        ),
        const SizedBox(height: MinimalTheme.spaceM),
        SizedBox(
          height: 160,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              AchievementBadge(
                title: 'First Book',
                description: 'Complete your first reading log',
                emoji: '📚',
                isEarned: true,
                earnedDate: DateTime.now().subtract(const Duration(days: 7)),
              ),
              const SizedBox(width: MinimalTheme.spaceM),
              AchievementBadge(
                title: 'Week Warrior',
                description: 'Read for 7 days straight',
                emoji: '🔥',
                isEarned: true,
                earnedDate: DateTime.now().subtract(const Duration(days: 2)),
              ),
              const SizedBox(width: MinimalTheme.spaceM),
              const AchievementBadge(
                title: 'Book Worm',
                description: 'Read 10 different books',
                emoji: '🐛',
                isEarned: false,
              ),
              const SizedBox(width: MinimalTheme.spaceM),
              const AchievementBadge(
                title: 'Speed Reader',
                description: 'Read for 60 minutes in one day',
                emoji: '⚡',
                isEarned: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNoChildrenView() {
    return EmptyState(
      icon: Icons.family_restroom,
      title: 'No Children Linked',
      message:
          'You don\'t have any children linked to your account yet. Please contact your school administrator.',
      buttonText: 'Contact Support',
      onButtonPressed: () {
        // Handle contact support
      },
    );
  }
}
