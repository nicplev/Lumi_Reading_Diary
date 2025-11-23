import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';
import 'allocation_screen.dart';
import 'teacher_profile_screen.dart';

class TeacherHomeScreenMinimal extends StatefulWidget {
  final UserModel user;

  const TeacherHomeScreenMinimal({
    super.key,
    required this.user,
  });

  @override
  State<TeacherHomeScreenMinimal> createState() =>
      _TeacherHomeScreenMinimalState();
}

class _TeacherHomeScreenMinimalState extends State<TeacherHomeScreenMinimal> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  int _selectedIndex = 0;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  bool _isLoading = true;
  final DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final List<ClassModel> classes = [];

      // Query classes within the teacher's school
      final classQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('teacherId', isEqualTo: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in classQuery.docs) {
        classes.add(ClassModel.fromFirestore(doc));
      }

      // Also load classes where user is assistant teacher
      final assistantQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('assistantTeacherId', isEqualTo: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in assistantQuery.docs) {
        final classModel = ClassModel.fromFirestore(doc);
        if (!classes.any((c) => c.id == classModel.id)) {
          classes.add(classModel);
        }
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
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.rosePink,
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardView(),
          _buildClassesView(),
          AllocationScreen(
            teacher: widget.user,
            selectedClass: _selectedClass,
          ),
          TeacherProfileScreen(user: widget.user),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
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
            horizontal: LumiSpacing.m,
            vertical: LumiSpacing.s,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.dashboard, 'Dashboard', 0),
              _buildNavItem(Icons.groups, 'Classes', 1),
              _buildNavItem(Icons.assignment, 'Allocate', 2),
              _buildNavItem(Icons.person, 'Profile', 3),
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
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.rosePink.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive
                  ? AppColors.rosePink
                  : AppColors.charcoal.withValues(alpha: 0.7),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: LumiTextStyles.label(
                color: isActive
                    ? AppColors.rosePink
                    : AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    if (_selectedClass == null) {
      return const Center(child: Text('No class selected'));
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // App Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(LumiSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.rosePink,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school,
                          color: AppColors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: LumiSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lumi Reading',
                              style: LumiTextStyles.h3(),
                            ),
                            Text(
                              'Hello ${widget.user.fullName.split(' ').first}',
                              style: LumiTextStyles.body(
                                color: AppColors.charcoal.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      LumiIconButton(
                        icon: Icons.notifications_outlined,
                        onPressed: () {},
                      ),
                    ],
                  ),
                  const SizedBox(height: LumiSpacing.xl),

                  // Class Selector
                  if (_classes.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _classes.map((classModel) {
                          final isSelected = classModel.id == _selectedClass!.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: LumiSpacing.s),
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedClass = classModel),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: LumiSpacing.m,
                                  vertical: LumiSpacing.s,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.rosePink
                                      : AppColors.charcoal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                                child: Text(
                                  classModel.name,
                                  style: LumiTextStyles.body(
                                    color: isSelected
                                        ? AppColors.white
                                        : AppColors.charcoal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: LumiSpacing.l),
                  ],

                  // Title
                  Text(
                    'Class Overview',
                    style: LumiTextStyles.h2(),
                  ),
                  Text(
                    _selectedClass!.name,
                    style: LumiTextStyles.h3(color: AppColors.rosePink),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(LumiSpacing.m),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Today's Progress
                _buildTodayProgress(_selectedClass!),
                const SizedBox(height: LumiSpacing.l),

                // Weekly Completion Rate
                _buildWeeklyProgress(_selectedClass!),
                const SizedBox(height: LumiSpacing.l),

                // Class Stats
                _buildClassStats(_selectedClass!),
                const SizedBox(height: LumiSpacing.l),

                // Recent Students
                _buildRecentStudents(_selectedClass!),
                const SizedBox(height: LumiSpacing.l),

                // Quick Actions
                _buildQuickActions(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayProgress(ClassModel classModel) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: classModel.id)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date',
              isLessThan:
                  Timestamp.fromDate(startOfDay.add(const Duration(days: 1))))
          .snapshots(),
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final completionRate = classModel.studentIds.isEmpty
            ? 0.0
            : (logs.length / classModel.studentIds.length);

        final totalMinutes =
            logs.fold<int>(0, (total, log) => total + log.minutesRead);
        final avgMinutes = logs.isEmpty ? 0 : totalMinutes ~/ logs.length;

        return LumiCard(
          child: Padding(
            padding: const EdgeInsets.all(LumiSpacing.l),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Progress',
                    style: LumiTextStyles.h3(),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rosePink,
                      borderRadius:
                          BorderRadius.circular(100),
                    ),
                    child: Text(
                      DateFormat('MMM dd').format(_selectedDate),
                      style: LumiTextStyles.label(color: AppColors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LumiSpacing.l),
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: completionRate,
                        strokeWidth: 12,
                        backgroundColor: AppColors.charcoal.withValues(alpha: 0.1),
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.rosePink),
                      ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${(completionRate * 100).toStringAsFixed(0)}%',
                              style: LumiTextStyles.h2(color: AppColors.rosePink),
                            ),
                            Text(
                              'Complete',
                              style: LumiTextStyles.label(
                                color: AppColors.charcoal.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: LumiSpacing.l),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(
                    Icons.groups,
                    '${logs.length}/${classModel.studentIds.length}',
                    'Students',
                    AppColors.skyBlue,
                  ),
                  _buildMiniStat(
                    Icons.timer,
                    '$avgMinutes',
                    'Avg Min',
                    AppColors.warmOrange,
                  ),
                  _buildMiniStat(
                    Icons.book,
                    '${logs.fold<int>(0, (total, log) => total + log.bookTitles.length)}',
                    'Books',
                    AppColors.rosePink,
                  ),
                ],
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(
      IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: LumiSpacing.s),
        Text(
          value,
          style: LumiTextStyles.h3(color: color),
        ),
        Text(
          label,
          style: LumiTextStyles.label(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyProgress(ClassModel classModel) {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
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

        // Group by day
        final Map<int, int> completionByDay = {};
        for (int i = 0; i < 7; i++) {
          final date = startOfWeek.add(Duration(days: i));
          final dayLogs = logs.where((log) =>
              log.date.year == date.year &&
              log.date.month == date.month &&
              log.date.day == date.day);
          completionByDay[i] = dayLogs.length;
        }

        return LumiCard(
          child: Padding(
            padding: const EdgeInsets.all(LumiSpacing.l),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly Completion',
                style: LumiTextStyles.h3(),
              ),
              const SizedBox(height: LumiSpacing.l),
              SizedBox(
                height: 150,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (index) {
                    final count = completionByDay[index] ?? 0;
                    final maxCount = classModel.studentIds.length;
                    final height = maxCount > 0
                        ? (count / maxCount * 120).clamp(10.0, 120.0)
                        : 10.0;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '$count',
                          style: LumiTextStyles.label(color: AppColors.charcoal),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: height,
                          decoration: BoxDecoration(
                            color: AppColors.rosePink,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                          style: LumiTextStyles.label(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  Widget _buildClassStats(ClassModel classModel) {
    return Row(
      children: [
        Expanded(
          child: LumiCard(
            child: Padding(
              padding: const EdgeInsets.all(LumiSpacing.m),
              child: Column(
                children: [
                  Icon(Icons.people, color: AppColors.skyBlue, size: 32),
                  const SizedBox(height: LumiSpacing.s),
                  Text(
                    '${classModel.studentIds.length}',
                    style: LumiTextStyles.h2(color: AppColors.skyBlue),
                  ),
                  Text(
                    'Students',
                    style: LumiTextStyles.label(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: LumiSpacing.m),
        Expanded(
          child: LumiCard(
            child: Padding(
              padding: const EdgeInsets.all(LumiSpacing.m),
              child: Column(
                children: [
                  Icon(Icons.calendar_today, color: AppColors.warmOrange, size: 32),
                  const SizedBox(height: LumiSpacing.s),
                  Text(
                    classModel.yearLevel?.toString() ?? '-',
                    style: LumiTextStyles.h2(color: AppColors.warmOrange),
                  ),
                  Text(
                    'Year Level',
                    style: LumiTextStyles.label(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentStudents(ClassModel classModel) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .where(FieldPath.documentId,
              whereIn: classModel.studentIds.take(10).toList())
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final students = snapshot.data!.docs
            .map((doc) => StudentModel.fromFirestore(doc))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Students',
              style: LumiTextStyles.h3(),
            ),
            const SizedBox(height: LumiSpacing.m),
            Wrap(
              spacing: LumiSpacing.m,
              runSpacing: LumiSpacing.m,
              children: students.take(10).map((student) {
                return _buildStudentAvatar(student);
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStudentAvatar(StudentModel student) {
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
              isLessThan:
                  Timestamp.fromDate(startOfDay.add(const Duration(days: 1))))
          .snapshots(),
      builder: (context, snapshot) {
        final hasLogged = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Column(
          children: [
            Stack(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: hasLogged
                        ? AppColors.mintGreen.withValues(alpha: 0.2)
                        : AppColors.rosePink.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      student.firstName[0].toUpperCase(),
                      style: LumiTextStyles.h3(
                        color: hasLogged
                            ? AppColors.mintGreen
                            : AppColors.rosePink,
                      ),
                    ),
                  ),
                ),
                if (hasLogged)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: AppColors.mintGreen,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 50,
              child: Text(
                student.firstName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LumiTextStyles.label(
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(LumiSpacing.l),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: LumiTextStyles.h3(),
          ),
          const SizedBox(height: LumiSpacing.m),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(
                Icons.assignment,
                'Allocate',
                AppColors.skyBlue,
                () => setState(() => _selectedIndex = 2),
              ),
              _buildActionButton(
                Icons.message,
                'Message',
                AppColors.rosePink,
                () {},
              ),
              _buildActionButton(
                Icons.download,
                'Export',
                AppColors.mintGreen,
                () {},
              ),
              _buildActionButton(
                Icons.notifications_active,
                'Nudge',
                AppColors.warmOrange,
                () {},
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildActionButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: LumiTextStyles.label(color: AppColors.charcoal),
          ),
        ],
      ),
    );
  }

  Widget _buildClassesView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LumiSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Classes',
              style: LumiTextStyles.h2(),
            ),
            const SizedBox(height: LumiSpacing.l),
            Expanded(
              child: ListView.builder(
                itemCount: _classes.length,
                itemBuilder: (context, index) {
                  final classModel = _classes[index];
                  return _buildClassCard(classModel);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard(ClassModel classModel) {
    return GestureDetector(
      onTap: () {
        context.push(
          '/teacher/class-detail/${classModel.id}',
          extra: {
            'user': widget.user,
            'classData': classModel,
          },
        );
      },
      child: LumiCard(
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.rosePink,
                borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
              ),
              child: const Icon(
                Icons.groups,
                color: AppColors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: LumiSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    classModel.name,
                    style: LumiTextStyles.h3(color: AppColors.charcoal),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${classModel.studentIds.length} students',
                    style: LumiTextStyles.body(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  if (classModel.yearLevel != null)
                    Text(
                      'Year ${classModel.yearLevel}',
                      style: LumiTextStyles.label(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoClassesView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LumiSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school,
              size: 80,
              color: AppColors.charcoal.withValues(alpha: 0.3),
            ),
            const SizedBox(height: LumiSpacing.l),
            Text(
              'No Classes Yet',
              style: LumiTextStyles.h2(),
            ),
            const SizedBox(height: LumiSpacing.s),
            Text(
              'You don\'t have any classes assigned yet. Please contact your school administrator.',
              textAlign: TextAlign.center,
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: LumiSpacing.l),
            LumiPrimaryButton(
              onPressed: _loadClasses,
              text: 'Refresh',
            ),
          ],
        ),
      ),
    );
  }
}
