import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
// Conditional import - use dart:io on mobile, stub on web
import 'dart:io' if (dart.library.html) '../../utils/io_stub.dart';

import '../../core/theme/app_colors.dart';
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
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text(widget.classModel.name),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.classModel.name),
        backgroundColor: AppColors.white,
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.gray,
                                    ),
                          ),
                        Text(
                          '${_students.length} Students',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
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
                          color: AppColors.lightGray,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Room ${widget.classModel.room}',
                          style: Theme.of(context).textTheme.labelMedium,
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
                    segments: const [
                      ButtonSegment(
                        value: 'week',
                        label: Text('This Week'),
                      ),
                      ButtonSegment(
                        value: 'month',
                        label: Text('This Month'),
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
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _sortBy,
                  items: const [
                    DropdownMenuItem(
                      value: 'name',
                      child: Text('Sort by Name'),
                    ),
                    DropdownMenuItem(
                      value: 'level',
                      child: Text('Sort by Level'),
                    ),
                    DropdownMenuItem(
                      value: 'streak',
                      child: Text('Sort by Streak'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _sortBy = value!;
                      _sortStudents(_students);
                    });
                  },
                  underline: const SizedBox(),
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
  final DateTime periodStart;
  final DateTime periodEnd;

  const _StudentCard({
    required this.student,
    required this.classModel,
    required this.periodStart,
    required this.periodEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
                  child: Text(
                    student.firstName[0].toUpperCase(),
                    style: TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.fullName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondaryPurple.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Level: ${student.currentReadingLevel ?? "Not set"}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: AppColors.secondaryPurple,
                                    fontWeight: FontWeight.bold,
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
                                color:
                                    AppColors.secondaryOrange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.local_fire_department,
                                    size: 12,
                                    color: AppColors.secondaryOrange,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${student.stats?.currentStreak}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: AppColors.secondaryOrange,
                                          fontWeight: FontWeight.bold,
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
                IconButton(
                  icon: const Icon(Icons.message_outlined),
                  onPressed: () {
                    // Send message to parents
                  },
                ),
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
                      color: AppColors.primaryBlue,
                    ),
                    _StatItem(
                      label: 'Total Min',
                      value: '$totalMinutes',
                      icon: Icons.timer,
                      color: AppColors.secondaryGreen,
                    ),
                    _StatItem(
                      label: 'Avg Min',
                      value: '$averageMinutes',
                      icon: Icons.trending_up,
                      color: AppColors.secondaryOrange,
                    ),
                  ],
                );
              },
            ),
          ],
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
