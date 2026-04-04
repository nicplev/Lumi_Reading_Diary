import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/teacher_class_card.dart';
import '../../core/widgets/lumi/teacher_alert_banner.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
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
    if (widget.user.role != UserRole.teacher &&
        widget.user.role != UserRole.schoolAdmin) {
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

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        ),
        title: const Text('Sign Out', style: TeacherTypography.h3),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TeacherTypography.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.teacherTheme(),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.teacherBackground,
        body: _buildLoadingView(),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.teacherBackground,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.teacherBackground,
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
          TeacherLibraryScreen(teacher: widget.user),
          TeacherSettingsScreen(user: widget.user),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
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
      bottom: false,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDashboardHero(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _DashboardStatsGrid(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
                const SizedBox(height: 20),
                if (_classes.length > 1) ...[
                  Text('Your Classes', style: TeacherTypography.h3),
                  const SizedBox(height: 12),
                  ..._classes.map((classModel) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                  const SizedBox(height: 10),
                ],
                Text('Weekly Activity', style: TeacherTypography.h3),
                const SizedBox(height: 12),
                _WeeklyEngagementChart(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
                const SizedBox(height: 12),
                _InactivityAlertBanner(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingView() {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: AppColors.teacherPrimary,
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LumiSkeleton(width: 200, height: 24),
                  SizedBox(height: 6),
                  LumiSkeleton(width: 140, height: 14),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      LumiSkeleton(width: 80, height: 36, borderRadius: 20),
                      SizedBox(width: 8),
                      LumiSkeleton(width: 96, height: 36, borderRadius: 20),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: const [
                Expanded(child: LumiSkeleton(height: 152, borderRadius: 24)),
                SizedBox(width: 12),
                Expanded(child: LumiSkeleton(height: 152, borderRadius: 24)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                Expanded(child: LumiSkeleton(height: 152, borderRadius: 24)),
                SizedBox(width: 12),
                Expanded(child: LumiSkeleton(height: 152, borderRadius: 24)),
              ],
            ),
            const SizedBox(height: 24),
            const LumiSkeleton(
              height: 280,
              borderRadius: 24,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.teacherPrimary.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -10,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          backgroundColor: AppColors.white,
          selectedItemColor: AppColors.teacherPrimary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: TeacherTypography.caption.copyWith(
            color: AppColors.teacherPrimary,
          ),
          unselectedLabelStyle: TeacherTypography.caption,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.groups_outlined),
              activeIcon: Icon(Icons.groups_rounded),
              label: 'Class',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book_rounded),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardHero() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';
    final firstName = widget.user.fullName.isNotEmpty
        ? widget.user.fullName.split(' ').first
        : 'Teacher';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.teacherPrimary,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, $firstName',
                      style: TeacherTypography.h2.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, MMMM d').format(DateTime.now()),
                      style: TeacherTypography.bodyMedium.copyWith(
                        color: AppColors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              _buildHeroIconButton(
                icon: Icons.notifications_outlined,
                onTap: () {
                  context.push('/teacher/notifications',
                      extra: widget.user);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildClassHeroChip(),
              const SizedBox(width: 8),
              _buildHeroPill(
                icon: Icons.people_alt_outlined,
                label: '${_selectedClass?.studentIds.length ?? 0} students',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClassHeroChip() {
    final label = _selectedClass?.name ?? 'Select Class';

    return Material(
      color: AppColors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _classes.length > 1
            ? () => _showClassSelectorBottomSheet(context)
            : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.class_outlined,
                size: 18,
                color: AppColors.white,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_classes.length > 1) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroPill({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: AppColors.white),
        ),
      ),
    );
  }


  Widget _buildNoClassesView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _handleSignOut,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back, color: AppColors.charcoal),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.teacherBorder),
                    boxShadow: TeacherDimensions.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: AppColors.teacherSurfaceTint,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Center(
                          child: LumiMascot(
                            mood: LumiMood.thinking,
                            size: 66,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No Classes Assigned',
                        style: TeacherTypography.h1,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your dashboard is ready, but you need an active class before classroom and library workflows become useful.',
                        style: TeacherTypography.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ask your school administrator to assign you to a class, then refresh here.',
                        style: TeacherTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      LumiPrimaryButton(
                        onPressed: _loadClasses,
                        text: 'Refresh Classes',
                        color: AppColors.teacherPrimary,
                        isFullWidth: true,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClassSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Class', style: TeacherTypography.h3),
            const SizedBox(height: 18),
            ..._classes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: _selectedClass?.id == c.id
                      ? AppColors.teacherSurfaceTint
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: _selectedClass?.id == c.id
                            ? AppColors.teacherPrimary.withValues(alpha: 0.18)
                            : AppColors.teacherBorder,
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: TeacherTypography.bodyLarge.copyWith(
                        fontWeight: _selectedClass?.id == c.id
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _selectedClass?.id == c.id
                            ? AppColors.teacherPrimary
                            : AppColors.charcoal,
                      ),
                    ),
                    subtitle: Text(
                      '${c.studentIds.length} students',
                      style: TeacherTypography.bodySmall,
                    ),
                    trailing: _selectedClass?.id == c.id
                        ? Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.teacherPrimary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 18,
                              color: AppColors.white,
                            ),
                          )
                        : null,
                    onTap: () {
                      setState(() => _selectedClass = c);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// DASHBOARD STATS GRID (2x2)
// ============================================

class _DashboardStatsGrid extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;

  const _DashboardStatsGrid({
    required this.classModel,
    required this.schoolId,
  });

  @override
  State<_DashboardStatsGrid> createState() => _DashboardStatsGridState();
}

class _DashboardStatsGridState extends State<_DashboardStatsGrid> {
  late Stream<QuerySnapshot> _logsStream;
  late Stream<QuerySnapshot> _studentsStream;

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  @override
  void didUpdateWidget(_DashboardStatsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStreams();
    }
  }

  void _initStreams() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    _logsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots();

    _studentsStream = widget.classModel.studentIds.isEmpty
        ? const Stream.empty()
        : FirebaseService.instance.firestore
            .collection('schools')
            .doc(widget.schoolId)
            .collection('students')
            .where(FieldPath.documentId,
                whereIn: widget.classModel.studentIds.take(10).toList())
            .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final totalStudents = widget.classModel.studentIds.length;

    return StreamBuilder<QuerySnapshot>(
      stream: _logsStream,
      builder: (context, logsSnapshot) {
        if (logsSnapshot.hasError) {
          debugPrint('Dashboard stats error: ${logsSnapshot.error}');
        }

        final logs = logsSnapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final uniqueStudentsToday = logs.map((l) => l.studentId).toSet();
        final readCount = uniqueStudentsToday.length;
        final totalBooks =
            logs.fold<int>(0, (total, log) => total + log.bookTitles.length);

        return StreamBuilder<QuerySnapshot>(
          stream: _studentsStream,
          builder: (context, studentsSnapshot) {
            if (studentsSnapshot.hasError) {
              debugPrint('Students stats error: ${studentsSnapshot.error}');
            }

            int onStreakCount = 0;
            if (studentsSnapshot.hasData) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              final yesterday = today.subtract(const Duration(days: 1));

              for (final doc in studentsSnapshot.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final stats = data['stats'] as Map<String, dynamic>?;
                if (stats == null || (stats['currentStreak'] ?? 0) <= 0) {
                  continue;
                }
                // Only count if they read today or yesterday
                final lastReadTs = stats['lastReadingDate'] as Timestamp?;
                if (lastReadTs == null) continue;
                final lastDay = DateTime(
                  lastReadTs.toDate().year,
                  lastReadTs.toDate().month,
                  lastReadTs.toDate().day,
                );
                if (lastDay.isAtSameMomentAs(today) ||
                    lastDay.isAtSameMomentAs(yesterday)) {
                  onStreakCount++;
                }
              }
            }

            final notReadCount = totalStudents - readCount;

            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusL),
                border: Border.all(color: AppColors.teacherBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today · ${widget.classModel.name}',
                    style: TeacherTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _CompactStat(
                        value: '$readCount',
                        label: 'Read',
                        color: AppColors.success,
                      ),
                      _statDivider(),
                      _CompactStat(
                        value: '$notReadCount',
                        label: 'Not yet',
                        color: notReadCount > 0
                            ? AppColors.warmOrange
                            : AppColors.textSecondary,
                      ),
                      _statDivider(),
                      _CompactStat(
                        value: '$onStreakCount',
                        label: 'On streak',
                        color: AppColors.teacherPrimary,
                      ),
                      _statDivider(),
                      _CompactStat(
                        value: '$totalBooks',
                        label: 'Books',
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

Widget _statDivider() {
  return Container(
    width: 1,
    height: 32,
    margin: const EdgeInsets.symmetric(horizontal: 12),
    color: AppColors.divider,
  );
}

class _CompactStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _CompactStat({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TeacherTypography.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ============================================
// WEEKLY ENGAGEMENT CHART
// ============================================

class _WeeklyEngagementChart extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;

  const _WeeklyEngagementChart({
    required this.classModel,
    required this.schoolId,
  });

  @override
  State<_WeeklyEngagementChart> createState() => _WeeklyEngagementChartState();
}

class _WeeklyEngagementChartState extends State<_WeeklyEngagementChart> {
  late Stream<QuerySnapshot> _weeklyStream;
  late DateTime _startOfWeek;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(_WeeklyEngagementChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
    }
  }

  void _initStream() {
    final now = DateTime.now();
    _startOfWeek = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    _weeklyStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfWeek))
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
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
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.teacherPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _weeklyStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('Weekly chart error: ${snapshot.error}');
              }

              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              final Map<int, int> completionByDay = {};
              for (int i = 0; i < 7; i++) {
                final date = _startOfWeek.add(Duration(days: i));
                final dayStudents = logs
                    .where((log) =>
                        log.date.year == date.year &&
                        log.date.month == date.month &&
                        log.date.day == date.day)
                    .map((log) => log.studentId)
                    .toSet();
                completionByDay[i] = dayStudents.length;
              }

              final todayIndex = DateTime.now().weekday - 1;
              final totalWeek =
                  completionByDay.values.fold<int>(0, (a, b) => a + b);
              final avgPerDay = todayIndex > 0
                  ? (totalWeek / (todayIndex + 1)).round()
                  : totalWeek;

              if (totalWeek == 0) {
                return SizedBox(
                  height: 100,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bar_chart_rounded,
                          size: 28,
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No reading logs this week yet',
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherSurfaceTint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bar_chart_rounded,
                          size: 18,
                          color: AppColors.teacherPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$totalWeek reading logs this week',
                            style: TeacherTypography.bodySmall.copyWith(
                              color: AppColors.charcoal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                        maxY: widget.classModel.studentIds.isEmpty
                            ? 1
                            : widget.classModel.studentIds.length.toDouble(),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                const days = [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun'
                                ];
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
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color:
                                AppColors.teacherBorder.withValues(alpha: 0.8),
                            strokeWidth: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherBackground,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Average: $avgPerDay/${widget.classModel.studentIds.length} students per night',
                      style: TeacherTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
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

class _InactivityAlertBanner extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;

  const _InactivityAlertBanner({
    required this.classModel,
    required this.schoolId,
  });

  @override
  State<_InactivityAlertBanner> createState() => _InactivityAlertBannerState();
}

class _InactivityAlertBannerState extends State<_InactivityAlertBanner> {
  late Stream<QuerySnapshot> _weeklyStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(_InactivityAlertBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
    }
  }

  void _initStream() {
    final now = DateTime.now();
    final startOfWeek =
        DateTime(now.year, now.month, now.day - (now.weekday - 1));

    _weeklyStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _weeklyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('Inactivity banner error: ${snapshot.error}');
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final studentsWhoRead = logs.map((l) => l.studentId).toSet();
        final inactiveCount =
            widget.classModel.studentIds.length - studentsWhoRead.length;

        if (inactiveCount <= 0) {
          return const TeacherAlertBanner(
            type: AlertBannerType.success,
            message: 'All students have logged reading this week!',
            emoji: '\uD83C\uDF89',
          );
        }

        return TeacherAlertBanner(
          type: AlertBannerType.info,
          message: '$inactiveCount students haven\'t logged reading this week',
        );
      },
    );
  }
}
