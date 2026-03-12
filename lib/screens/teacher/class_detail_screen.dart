import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
// Conditional import - use dart:io on mobile, stub on web
import 'dart:io' if (dart.library.html) '../../utils/io_stub.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';

class ClassDetailScreen extends StatefulWidget {
  final ClassModel classModel;
  final UserModel teacher;

  const ClassDetailScreen({
    super.key,
    required this.classModel,
    required this.teacher,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  List<StudentModel> _students = [];
  bool _isLoading = true;
  String _sortBy = 'name';
  final DateTime _selectedPeriod = DateTime.now();
  String _periodType = 'week'; // 'week' or 'month'

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final students = <StudentModel>[];
      for (String studentId in widget.classModel.studentIds) {
        final doc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.teacher.schoolId)
            .collection('students')
            .doc(studentId)
            .get();
        if (doc.exists) {
          students.add(StudentModel.fromFirestore(doc));
        }
      }

      _sortStudents(students);

      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading students: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sortStudents(List<StudentModel> students) {
    switch (_sortBy) {
      case 'name':
        students.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'level':
        students.sort((a, b) {
          final levelA = a.currentReadingLevel ?? 'ZZ';
          final levelB = b.currentReadingLevel ?? 'ZZ';
          return levelA.compareTo(levelB);
        });
        break;
      case 'streak':
        students.sort((a, b) {
          final streakA = a.stats?.currentStreak ?? 0;
          final streakB = b.stats?.currentStreak ?? 0;
          return streakB.compareTo(streakA);
        });
        break;
    }
  }

  Future<void> _exportToCSV() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get reading logs for the period
      final startDate = _getStartDate();
      final endDate = _getEndDate();

      final logsQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.teacher.schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final logs = logsQuery.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      // Create CSV data
      final List<List<String>> csvData = [
        // Headers
        [
          'Student Name',
          'Reading Level',
          'Total Days',
          'Days Completed',
          'Total Minutes',
          'Average Minutes',
          'Current Streak',
          'Books Read',
        ],
      ];

      // Add student data
      for (final student in _students) {
        final studentLogs =
            logs.where((log) => log.studentId == student.id).toList();
        final totalMinutes =
            studentLogs.fold<int>(0, (sum, log) => sum + log.minutesRead);
        final averageMinutes =
            studentLogs.isEmpty ? 0 : totalMinutes ~/ studentLogs.length;
        final booksRead =
            studentLogs.fold<int>(0, (sum, log) => sum + log.bookTitles.length);

        csvData.add([
          student.fullName,
          student.currentReadingLevel ?? 'Not set',
          _getTotalDaysInPeriod().toString(),
          studentLogs.length.toString(),
          totalMinutes.toString(),
          averageMinutes.toString(),
          (student.stats?.currentStreak ?? 0).toString(),
          booksRead.toString(),
        ]);
      }

      // Convert to CSV string
      const converter = ListToCsvConverter();
      final csvString = converter.convert(csvData);

      // Save to file
      final directory = await getTemporaryDirectory();
      final fileName =
          'class_report_${widget.classModel.name}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.csv';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(csvString);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Class Report - ${widget.classModel.name}',
      );
    } catch (e) {
      debugPrint('Error exporting to CSV: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export data')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  DateTime _getStartDate() {
    if (_periodType == 'week') {
      return _selectedPeriod
          .subtract(Duration(days: _selectedPeriod.weekday - 1));
    } else {
      return DateTime(_selectedPeriod.year, _selectedPeriod.month, 1);
    }
  }

  DateTime _getEndDate() {
    if (_periodType == 'week') {
      final startOfWeek = _getStartDate();
      return startOfWeek.add(const Duration(days: 6));
    } else {
      return DateTime(_selectedPeriod.year, _selectedPeriod.month + 1, 0);
    }
  }

  int _getTotalDaysInPeriod() {
    return _getEndDate().difference(_getStartDate()).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            widget.classModel.name,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: AppColors.teacherPrimary,
          foregroundColor: AppColors.white,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.teacherPrimary,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.classModel.name,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToCSV,
          ),
        ],
      ),
      body: Column(
        children: [
          // Class info header
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.classModel.yearLevel != null)
                          Text(
                            'Year ${widget.classModel.yearLevel}',
                            style: TeacherTypography.bodySmall,
                          ),
                        Text(
                          '${_students.length} Students',
                          style: TeacherTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (widget.classModel.room != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.teacherPrimaryLight,
                          borderRadius: BorderRadius.circular(
                              TeacherDimensions.radiusRound),
                        ),
                        child: Text(
                          'Room ${widget.classModel.room}',
                          style: TeacherTypography.caption.copyWith(
                            color: AppColors.teacherPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Period selector
          Container(
            color: AppColors.white,
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.teacherPrimary,
                      selectedForegroundColor: AppColors.white,
                      backgroundColor: AppColors.white,
                      foregroundColor: AppColors.charcoal,
                      side: const BorderSide(color: AppColors.teacherPrimary),
                    ),
                    segments: [
                      ButtonSegment(
                        value: 'week',
                        label:
                            Text('This Week', style: TeacherTypography.caption),
                      ),
                      ButtonSegment(
                        value: 'month',
                        label: Text('This Month',
                            style: TeacherTypography.caption),
                      ),
                    ],
                    selected: {_periodType},
                    onSelectionChanged: (value) {
                      setState(() {
                        _periodType = value.first;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _sortBy,
                  style: TeacherTypography.bodyMedium
                      .copyWith(color: AppColors.charcoal),
                  items: [
                    DropdownMenuItem(
                      value: 'name',
                      child: Text('Sort by Name',
                          style: TeacherTypography.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'level',
                      child: Text('Sort by Level',
                          style: TeacherTypography.bodySmall),
                    ),
                    DropdownMenuItem(
                      value: 'streak',
                      child: Text('Sort by Streak',
                          style: TeacherTypography.bodySmall),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _sortBy = value!;
                      _sortStudents(_students);
                    });
                  },
                  underline: const SizedBox(),
                  icon: Icon(Icons.keyboard_arrow_down,
                      size: 18, color: AppColors.teacherPrimary),
                ),
              ],
            ),
          ),

          // Student list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final student = _students[index];
                return _StudentCard(
                  student: student,
                  classModel: widget.classModel,
                  teacher: widget.teacher,
                  periodStart: _getStartDate(),
                  periodEnd: _getEndDate(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final StudentModel student;
  final ClassModel classModel;
  final UserModel teacher;
  final DateTime periodStart;
  final DateTime periodEnd;

  const _StudentCard({
    required this.student,
    required this.classModel,
    required this.teacher,
    required this.periodStart,
    required this.periodEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () {
          context.push(
            '/teacher/student-detail/${student.id}',
            extra: {
              'teacher': teacher,
              'student': student,
              'classModel': classModel,
            },
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: AppColors.teacherPrimaryLight,
                    child: Text(
                      student.firstName[0].toUpperCase(),
                      style: TeacherTypography.h3
                          .copyWith(color: AppColors.teacherPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.fullName,
                          style: TeacherTypography.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.teacherPrimaryLight,
                                borderRadius: BorderRadius.circular(
                                    TeacherDimensions.radiusRound),
                              ),
                              child: Text(
                                'Level: ${student.currentReadingLevel ?? "Not set"}',
                                style: TeacherTypography.caption.copyWith(
                                  color: AppColors.teacherPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if ((student.stats?.currentStreak ?? 0) > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warmOrange
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(
                                      TeacherDimensions.radiusRound),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department,
                                      size: 12,
                                      color: AppColors.warmOrange,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${student.stats?.currentStreak}',
                                      style: TeacherTypography.caption.copyWith(
                                        color: AppColors.warmOrange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: 20, color: AppColors.textSecondary),
                ],
              ),

              const SizedBox(height: 12),
              // Period stats
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.instance.firestore
                    .collection('readingLogs')
                    .where('studentId', isEqualTo: student.id)
                    .where('date',
                        isGreaterThanOrEqualTo: Timestamp.fromDate(periodStart))
                    .where('date',
                        isLessThanOrEqualTo: Timestamp.fromDate(periodEnd))
                    .snapshots(),
                builder: (context, snapshot) {
                  final logs = snapshot.data?.docs
                          .map((doc) => ReadingLogModel.fromFirestore(doc))
                          .toList() ??
                      [];

                  final daysCompleted = logs.length;
                  final totalMinutes =
                      logs.fold<int>(0, (sum, log) => sum + log.minutesRead);
                  final averageMinutes =
                      logs.isEmpty ? 0 : totalMinutes ~/ logs.length;

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatItem(
                        label: 'Days',
                        value: '$daysCompleted',
                        icon: Icons.calendar_today,
                        color: AppColors.teacherPrimary,
                      ),
                      _StatItem(
                        label: 'Total Min',
                        value: '$totalMinutes',
                        icon: Icons.timer,
                        color: AppColors.mintGreen,
                      ),
                      _StatItem(
                        label: 'Avg Min',
                        value: '$averageMinutes',
                        icon: Icons.trending_up,
                        color: AppColors.warmOrange,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TeacherTypography.bodyMedium
              .copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TeacherTypography.bodySmall,
        ),
      ],
    );
  }
}
