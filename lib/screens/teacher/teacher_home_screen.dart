import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_stat_card.dart';
import '../../core/widgets/lumi/teacher_class_card.dart';
import '../../core/widgets/lumi/teacher_alert_banner.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';
import 'teacher_classroom_screen.dart';
import 'teacher_library_screen.dart';
import 'teacher_settings_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  final UserModel user;

  const TeacherHomeScreen({
    super.key,
    required this.user,
  });

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  int _selectedIndex = 0;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Role guard: redirect if user is not a teacher or admin
    if (widget.user.role != UserRole.teacher && widget.user.role != UserRole.schoolAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/auth/login');
      });
      return;
    }
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final List<ClassModel> classes = [];

      final classQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('teacherIds', arrayContains: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in classQuery.docs) {
        classes.add(ClassModel.fromFirestore(doc));
      }

      setState(() {
        _classes = classes;
        if (classes.isNotEmpty) {
          _selectedClass = classes.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading classes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.teacherPrimary,
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardView(),
          TeacherClassroomScreen(
            teacher: widget.user,
            selectedClass: _selectedClass,
            classes: _classes,
            onClassChanged: (c) => setState(() => _selectedClass = c),
          ),
          const TeacherLibraryScreen(),
          TeacherSettingsScreen(user: widget.user),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.teacherPrimary,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people_outlined),
            activeIcon: Icon(Icons.people),
            label: 'Class',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book_outlined),
            activeIcon: Icon(Icons.menu_book),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  // ============================================
  // DASHBOARD VIEW
  // ============================================

  Widget _buildDashboardView() {
    if (_selectedClass == null) {
      return const Center(child: Text('No class selected'));
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Gradient header
          SliverToBoxAdapter(child: _buildGradientHeader()),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 2x2 Stats Grid
                _DashboardStatsGrid(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
                const SizedBox(height: 16),

                // Class Cards (only if multiple classes)
                if (_classes.length > 1) ...[
                  Text('My Classes', style: TeacherTypography.h3),
                  const SizedBox(height: 8),
                  ..._classes.map((classModel) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TeacherClassCard(
                        className: classModel.name,
                        studentCount: classModel.studentIds.length,
                        readingRate: 0.0,
                        onTap: () {
                          context.push(
                            '/teacher/class-detail/${classModel.id}',
                            extra: {
                              'user': widget.user,
                              'classData': classModel,
                            },
                          );
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                ],

                // Weekly Engagement Chart
                _WeeklyEngagementChart(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
                const SizedBox(height: 16),

                // Alert Banner
                _InactivityAlertBanner(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.teacherGradient,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, ${widget.user.fullName.isNotEmpty ? widget.user.fullName.split(' ').first : 'Teacher'}!',
                  style: TeacherTypography.h2.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (_classes.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: DropdownButton<ClassModel>(
                    value: _selectedClass,
                    items: _classes.map((classModel) {
                      return DropdownMenuItem(
                        value: classModel,
                        child: Text(classModel.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedClass = value);
                    },
                    underline: const SizedBox(),
                    style: TeacherTypography.bodyMedium.copyWith(color: AppColors.white),
                    dropdownColor: AppColors.teacherPrimary,
                    iconEnabledColor: AppColors.white,
                    isDense: true,
                  ),
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: AppColors.white,
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoClassesView() {
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text('Are you sure you want to sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _firebaseService.signOut();
                  if (mounted) context.go('/auth/login');
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LumiMascot(mood: LumiMood.thinking, size: 150),
                const SizedBox(height: 24),
                Text(
                  'No Classes Assigned',
                  style: TeacherTypography.h1,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please contact your school administrator to be assigned to a class.',
                  style: TeacherTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// DASHBOARD STATS GRID (2x2)
// ============================================

class _DashboardStatsGrid extends StatelessWidget {
  final ClassModel classModel;
  final String schoolId;

  const _DashboardStatsGrid({
    required this.classModel,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: classModel.id)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .snapshots(),
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final readCount = logs.length;
        final totalStudents = classModel.studentIds.length;
        final totalBooks = logs.fold<int>(0, (sum, log) => sum + log.bookTitles.length);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TeacherStatCard(
                    icon: Icons.people,
                    iconColor: AppColors.teacherPrimary,
                    iconBgColor: AppColors.teacherPrimaryLight,
                    value: '$totalStudents',
                    label: 'Students',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TeacherStatCard(
                    icon: Icons.check_circle,
                    iconColor: const Color(0xFF4CAF50),
                    iconBgColor: const Color(0xFFE8F5E9),
                    value: '$readCount',
                    label: 'Read Today',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TeacherStatCard(
                    icon: Icons.local_fire_department,
                    iconColor: AppColors.warmOrange,
                    iconBgColor: AppColors.warmOrange.withValues(alpha: 0.15),
                    value: '—',
                    label: 'On Streak',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TeacherStatCard(
                    icon: Icons.menu_book,
                    iconColor: AppColors.decodableBlue,
                    iconBgColor: const Color(0xFFE3F2FD),
                    value: '$totalBooks',
                    label: 'Books Today',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

// ============================================
// WEEKLY ENGAGEMENT CHART
// ============================================

class _WeeklyEngagementChart extends StatelessWidget {
  final ClassModel classModel;
  final String schoolId;

  const _WeeklyEngagementChart({
    required this.classModel,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly Reading Activity', style: TeacherTypography.h3),
              Text(
                'This Week',
                style: TeacherTypography.bodySmall.copyWith(
                  color: AppColors.teacherPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.firestore
                .collection('schools')
                .doc(schoolId)
                .collection('readingLogs')
                .where('classId', isEqualTo: classModel.id)
                .where('date',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
                .snapshots(),
            builder: (context, snapshot) {
              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              final Map<int, int> completionByDay = {};
              for (int i = 0; i < 7; i++) {
                final date = startOfWeek.add(Duration(days: i));
                final dayLogs = logs.where((log) =>
                    log.date.year == date.year &&
                    log.date.month == date.month &&
                    log.date.day == date.day);
                completionByDay[i] = dayLogs.length;
              }

              final todayIndex = DateTime.now().weekday - 1;
              final totalWeek = completionByDay.values.fold<int>(0, (a, b) => a + b);
              final avgPerDay = todayIndex > 0
                  ? (totalWeek / (todayIndex + 1)).round()
                  : totalWeek;

              return Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: BarChart(
                      BarChartData(
                        barGroups: List.generate(7, (index) {
                          Color barColor;
                          if (index < todayIndex) {
                            barColor = AppColors.teacherPrimary;
                          } else if (index == todayIndex) {
                            barColor = AppColors.teacherAccent;
                          } else {
                            barColor = AppColors.divider;
                          }

                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: completionByDay[index]?.toDouble() ?? 0,
                                color: barColor,
                                width: 32,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                              ),
                            ],
                          );
                        }),
                        maxY: classModel.studentIds.length.toDouble(),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    days[value.toInt()],
                                    style: TeacherTypography.caption,
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(show: false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Average: $avgPerDay/${classModel.studentIds.length} students per night',
                    style: TeacherTypography.bodySmall,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================
// INACTIVITY ALERT BANNER
// ============================================

class _InactivityAlertBanner extends StatelessWidget {
  final ClassModel classModel;
  final String schoolId;

  const _InactivityAlertBanner({
    required this.classModel,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: classModel.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .snapshots(),
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final studentsWhoRead = logs.map((l) => l.studentId).toSet();
        final inactiveCount = classModel.studentIds.length - studentsWhoRead.length;

        if (inactiveCount <= 0) {
          return const TeacherAlertBanner(
            type: AlertBannerType.success,
            message: 'All students have logged reading this week!',
            emoji: '\uD83C\uDF89',
          );
        }

        return TeacherAlertBanner(
          type: AlertBannerType.warning,
          message: '$inactiveCount students haven\'t logged reading this week',
        );
      },
    );
  }
}
