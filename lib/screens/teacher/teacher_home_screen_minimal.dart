import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/minimal_theme.dart';
import '../../core/widgets/minimal/minimal_widgets.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';
import 'class_detail_screen.dart';
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
        backgroundColor: MinimalTheme.cream,
        body: const Center(
          child: CircularProgressIndicator(
            color: MinimalTheme.primaryPurple,
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: MinimalTheme.cream,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: MinimalTheme.cream,
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
                          Icons.school,
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

                  // Class Selector
                  if (_classes.length > 1) ...[
                    PillTabBar(
                      tabs: _classes.map((c) => c.name).toList(),
                      selectedIndex: _classes
                          .indexWhere((c) => c.id == _selectedClass!.id),
                      onTabSelected: (index) {
                        setState(() {
                          _selectedClass = _classes[index];
                        });
                      },
                    ),
                    const SizedBox(height: MinimalTheme.spaceL),
                  ],

                  // Title
                  Text(
                    'Class Overview',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  Text(
                    _selectedClass!.name,
                    style: const TextStyle(
                      fontSize: 18,
                      color: MinimalTheme.primaryPurple,
                      fontWeight: FontWeight.w600,
                    ),
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
                // Today's Progress
                _buildTodayProgress(_selectedClass!),
                const SizedBox(height: MinimalTheme.spaceL),

                // Weekly Completion Rate
                _buildWeeklyProgress(_selectedClass!),
                const SizedBox(height: MinimalTheme.spaceL),

                // Class Stats
                _buildClassStats(_selectedClass!),
                const SizedBox(height: MinimalTheme.spaceL),

                // Recent Students
                _buildRecentStudents(_selectedClass!),
                const SizedBox(height: MinimalTheme.spaceL),

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

        return RoundedCard(
          padding: const EdgeInsets.all(MinimalTheme.spaceL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Today\'s Progress',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: MinimalTheme.purpleGradient,
                      borderRadius:
                          BorderRadius.circular(MinimalTheme.radiusPill),
                    ),
                    child: Text(
                      DateFormat('MMM dd').format(_selectedDate),
                      style: const TextStyle(
                        color: MinimalTheme.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MinimalTheme.spaceL),
              CircularProgress(
                progress: completionRate,
                label: '${(completionRate * 100).toStringAsFixed(0)}%',
                sublabel: 'Complete',
                size: 140,
              ),
              const SizedBox(height: MinimalTheme.spaceL),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat(
                    Icons.groups,
                    '${logs.length}/${classModel.studentIds.length}',
                    'Students',
                    MinimalTheme.blue,
                  ),
                  _buildMiniStat(
                    Icons.timer,
                    '$avgMinutes',
                    'Avg Min',
                    MinimalTheme.orange,
                  ),
                  _buildMiniStat(
                    Icons.book,
                    '${logs.fold<int>(0, (total, log) => total + log.bookTitles.length)}',
                    'Books',
                    MinimalTheme.primaryPurple,
                  ),
                ],
              ),
            ],
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
        const SizedBox(height: MinimalTheme.spaceS),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: MinimalTheme.textSecondary,
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

        return RoundedCard(
          padding: const EdgeInsets.all(MinimalTheme.spaceL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weekly Completion',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: MinimalTheme.spaceL),
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
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MinimalTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: height,
                          decoration: BoxDecoration(
                            gradient: MinimalTheme.purpleGradient,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                          style: const TextStyle(
                            fontSize: 12,
                            color: MinimalTheme.textSecondary,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClassStats(ClassModel classModel) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            icon: Icons.people,
            value: '${classModel.studentIds.length}',
            label: 'Students',
            iconColor: MinimalTheme.blue,
          ),
        ),
        const SizedBox(width: MinimalTheme.spaceM),
        Expanded(
          child: StatCard(
            icon: Icons.calendar_today,
            value: classModel.yearLevel?.toString() ?? '-',
            label: 'Year Level',
            iconColor: MinimalTheme.orange,
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: MinimalTheme.spaceM),
            Wrap(
              spacing: MinimalTheme.spaceM,
              runSpacing: MinimalTheme.spaceM,
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
                        ? MinimalTheme.green.withValues(alpha: 0.2)
                        : MinimalTheme.lightPurple,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      student.firstName[0].toUpperCase(),
                      style: TextStyle(
                        color: hasLogged
                            ? MinimalTheme.green
                            : MinimalTheme.primaryPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
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
                        color: MinimalTheme.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle,
                        color: MinimalTheme.green,
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
                style: const TextStyle(
                  fontSize: 11,
                  color: MinimalTheme.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return RoundedCard(
      padding: const EdgeInsets.all(MinimalTheme.spaceL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildActionButton(
                Icons.assignment,
                'Allocate',
                MinimalTheme.blue,
                () => setState(() => _selectedIndex = 2),
              ),
              _buildActionButton(
                Icons.message,
                'Message',
                MinimalTheme.primaryPurple,
                () {},
              ),
              _buildActionButton(
                Icons.download,
                'Export',
                MinimalTheme.green,
                () {},
              ),
              _buildActionButton(
                Icons.notifications_active,
                'Nudge',
                MinimalTheme.orange,
                () {},
              ),
            ],
          ),
        ],
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
            style: const TextStyle(
              fontSize: 12,
              color: MinimalTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassesView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MinimalTheme.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Classes',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            const SizedBox(height: MinimalTheme.spaceL),
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
    return AnimatedRoundedCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ClassDetailScreen(
              classModel: classModel,
              teacher: widget.user,
            ),
          ),
        );
      },
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: MinimalTheme.purpleGradient,
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
              boxShadow: MinimalTheme.softShadow(),
            ),
            child: const Icon(
              Icons.groups,
              color: MinimalTheme.white,
              size: 32,
            ),
          ),
          const SizedBox(width: MinimalTheme.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classModel.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: MinimalTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${classModel.studentIds.length} students',
                  style: const TextStyle(
                    fontSize: 14,
                    color: MinimalTheme.textSecondary,
                  ),
                ),
                if (classModel.yearLevel != null)
                  Text(
                    'Year ${classModel.yearLevel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MinimalTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: MinimalTheme.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildNoClassesView() {
    return EmptyState(
      icon: Icons.school,
      title: 'No Classes Yet',
      message:
          'You don\'t have any classes assigned yet. Please contact your school administrator.',
      buttonText: 'Refresh',
      onButtonPressed: _loadClasses,
    );
  }
}
