import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/liquid_glass_theme.dart';
import '../../core/widgets/glass/glass_widgets.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';
import 'class_detail_screen.dart';
import 'allocation_screen.dart';
import 'teacher_profile_screen.dart';
import '../auth/login_screen.dart';

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
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final List<ClassModel> classes = [];

      // Using nested structure - query classes within the teacher's school
      // Query using teacherIds array to find all classes where this teacher is assigned
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

    if (_classes.isEmpty) {
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LiquidGlassTheme.backgroundGradient,
          ),
          child: _buildNoClassesView(),
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
            _buildDashboardView(),
            _buildClassesView(),
            AllocationScreen(
              teacher: widget.user,
              selectedClass: _selectedClass,
            ),
            TeacherProfileScreen(user: widget.user),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.groups),
            label: 'Classes',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Allocate',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
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
          // App Bar with class selector
          SliverAppBar(
            floating: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello, ${widget.user.fullName.isNotEmpty ? widget.user.fullName.split(' ').first : 'Teacher'}!',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
                if (_classes.length > 1)
                  DropdownButton<ClassModel>(
                    value: _selectedClass,
                    items: _classes.map((classModel) {
                      return DropdownMenuItem(
                        value: classModel,
                        child: Text(classModel.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClass = value;
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
                    _selectedClass!.name,
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
                // Today's Overview Card
                _TodayOverviewCard(
                  classModel: _selectedClass!,
                  selectedDate: _selectedDate,
                  schoolId: widget.user.schoolId!,
                  onDateChanged: (date) {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                ),

                const SizedBox(height: 16),

                // Class Progress Chart
                _ClassProgressChart(
                  classModel: _selectedClass!,
                  schoolId: widget.user.schoolId!,
                ),

                const SizedBox(height: 16),

                // Students Grid
                _StudentsGrid(
                  classModel: _selectedClass!,
                  selectedDate: _selectedDate,
                  schoolId: widget.user.schoolId!,
                ),

                const SizedBox(height: 16),

                // Quick Actions
                _QuickActionsCard(
                  classModel: _selectedClass!,
                  onAction: (action) {
                    _handleQuickAction(action);
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassesView() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(LiquidGlassTheme.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Classes',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGray,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_classes.length} active ${_classes.length == 1 ? 'class' : 'classes'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _classes.length,
              itemBuilder: (context, index) {
                final classModel = _classes[index];
                return _ClassCard(
                  classModel: classModel,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  Widget _buildNoClassesView() {
    return SafeArea(
      child: Stack(
        children: [
          // Back button in top-left corner
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: AppColors.darkGray,
              ),
              onPressed: _handleSignOut,
              tooltip: 'Sign Out',
            ),
          ),
          // Main content
          Padding(
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
                  'No Classes Assigned',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGray,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please contact your school administrator to be assigned to a class.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray,
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

  void _handleQuickAction(String action) {
    switch (action) {
      case 'allocate':
        setState(() {
          _selectedIndex = 2; // Navigate to allocation tab
        });
        break;
      case 'message':
        // Navigate to messaging
        break;
      case 'export':
        // Handle export
        break;
      case 'nudge':
        // Send nudges
        break;
    }
  }
}

class _TodayOverviewCard extends StatelessWidget {
  final ClassModel classModel;
  final DateTime selectedDate;
  final Function(DateTime) onDateChanged;
  final String schoolId;

  const _TodayOverviewCard({
    required this.classModel,
    required this.selectedDate,
    required this.onDateChanged,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
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
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    onDateChanged(picked);
                  }
                },
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  DateFormat('MMM dd').format(selectedDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.firestore
                .collection('schools')
                .doc(schoolId)
                .collection('readingLogs')
                .where('classId', isEqualTo: classModel.id)
                .where('date',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
                    ))
                .where('date',
                    isLessThan: Timestamp.fromDate(
                      DateTime(selectedDate.year, selectedDate.month, selectedDate.day + 1),
                    ))
                .snapshots(),
            builder: (context, snapshot) {
              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              final completionRate = classModel.studentIds.isEmpty
                  ? 0.0
                  : (logs.length / classModel.studentIds.length * 100);

              final totalMinutes = logs.fold<int>(0, (sum, log) => sum + log.minutesRead);
              final averageMinutes = logs.isEmpty ? 0 : totalMinutes ~/ logs.length;

              return Column(
                children: [
                  // Circular progress indicator
                  SizedBox(
                    height: 120,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 120,
                          height: 120,
                          child: CircularProgressIndicator(
                            value: completionRate / 100,
                            strokeWidth: 12,
                            backgroundColor: AppColors.lightGray,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              completionRate >= 80
                                  ? AppColors.secondaryGreen
                                  : completionRate >= 50
                                      ? AppColors.secondaryYellow
                                      : AppColors.error,
                            ),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${completionRate.toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkGray,
                                  ),
                            ),
                            Text(
                              'Complete',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.gray,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        icon: Icons.groups,
                        value: '${logs.length}/${classModel.studentIds.length}',
                        label: 'Students',
                        color: AppColors.primaryBlue,
                      ),
                      _StatItem(
                        icon: Icons.timer,
                        value: '$averageMinutes',
                        label: 'Avg Minutes',
                        color: AppColors.secondaryOrange,
                      ),
                      _StatItem(
                        icon: Icons.book,
                        value: '${logs.fold<int>(0, (sum, log) => sum + log.bookTitles.length)}',
                        label: 'Books',
                        color: AppColors.secondaryPurple,
                      ),
                    ],
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

class _ClassProgressChart extends StatelessWidget {
  final ClassModel classModel;
  final String schoolId;

  const _ClassProgressChart({
    required this.classModel,
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
            'Weekly Trend',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
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

              return SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    barGroups: List.generate(7, (index) {
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: completionByDay[index]?.toDouble() ?? 0,
                            color: AppColors.primaryBlue,
                            width: 30,
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
                            final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                            return Text(
                              days[value.toInt()],
                              style: const TextStyle(fontSize: 12),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (value, meta) {
                            return Text(
                              '${value.toInt()}',
                              style: const TextStyle(fontSize: 10),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: true),
                  ),
                ),
              );
              },
            ),
          ],
        ),
      );
  }
}

class _StudentsGrid extends StatelessWidget {
  final ClassModel classModel;
  final DateTime selectedDate;
  final String schoolId;

  const _StudentsGrid({
    required this.classModel,
    required this.selectedDate,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Students',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              TextButton(
                onPressed: () {
                  // Navigate to student list
                },
                child: const Text('See All'),
              ),
            ],
          ),
          const SizedBox(height: LiquidGlassTheme.spacingSm),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.instance.firestore
                .collection('schools')
                .doc(schoolId)
                .collection('students')
                .where(FieldPath.documentId, whereIn: classModel.studentIds.take(10).toList())
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final students = snapshot.data!.docs
                  .map((doc) => StudentModel.fromFirestore(doc))
                  .toList();

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 0.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: students.length,
                itemBuilder: (context, index) {
                    final student = students[index];
                    return _StudentAvatar(
                      student: student,
                      selectedDate: selectedDate,
                      schoolId: schoolId,
                    );
                  },
                );
              },
            ),
          ],
        ),
      );
  }
}

class _StudentAvatar extends StatelessWidget {
  final StudentModel student;
  final DateTime selectedDate;
  final String schoolId;

  const _StudentAvatar({
    required this.student,
    required this.selectedDate,
    required this.schoolId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: student.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(
                DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
              ))
          .where('date',
              isLessThan: Timestamp.fromDate(
                DateTime(selectedDate.year, selectedDate.month, selectedDate.day + 1),
              ))
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final hasLogged = snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: hasLogged
                      ? AppColors.secondaryGreen.withValues(alpha: 0.2)
                      : AppColors.lightGray,
                  child: Text(
                    student.firstName[0].toUpperCase(),
                    style: TextStyle(
                      color: hasLogged ? AppColors.secondaryGreen : AppColors.gray,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (hasLogged)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: AppColors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              student.firstName,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  final ClassModel classModel;
  final Function(String) onAction;

  const _QuickActionsCard({
    required this.classModel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: LiquidGlassTheme.spacingMd),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionButton(
                icon: Icons.assignment,
                label: 'Allocate',
                color: AppColors.primaryBlue,
                onTap: () => onAction('allocate'),
              ),
              _ActionButton(
                icon: Icons.message,
                label: 'Message',
                color: AppColors.secondaryPurple,
                onTap: () => onAction('message'),
              ),
              _ActionButton(
                icon: Icons.download,
                label: 'Export',
                color: AppColors.secondaryGreen,
                onTap: () => onAction('export'),
              ),
              _ActionButton(
                icon: Icons.notifications_active,
                label: 'Nudge',
                color: AppColors.secondaryOrange,
                onTap: () => onAction('nudge'),
              ),
              ],
            ),
          ],
        ),
      );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(LiquidGlassTheme.spacingSm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(LiquidGlassTheme.spacingSm),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: LiquidGlassTheme.softShadow(),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: LiquidGlassTheme.spacingXs),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassModel classModel;
  final VoidCallback onTap;

  const _ClassCard({
    required this.classModel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedGlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(LiquidGlassTheme.spacingLg),
        child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LiquidGlassTheme.teacherGradient,
              borderRadius: BorderRadius.circular(LiquidGlassTheme.radiusMd),
              boxShadow: LiquidGlassTheme.glowShadow(
                color: AppColors.teacherColor,
                blurRadius: 8,
                spreadRadius: 0,
              ),
            ),
            child: const Icon(
              Icons.groups,
              color: AppColors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: LiquidGlassTheme.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classModel.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${classModel.studentIds.length} students',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
                if (classModel.yearLevel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Year ${classModel.yearLevel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.gray,
          ),
        ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray,
              ),
        ),
      ],
    );
  }
}