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
import '../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../data/models/reading_level_option.dart';
import '../../data/models/school_model.dart';
import '../../services/firebase_service.dart';
import '../../services/platform_config_service.dart';
import '../../services/reading_level_service.dart';

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
  final ReadingLevelService _readingLevelService = ReadingLevelService();
  List<StudentModel> _students = [];
  List<ReadingLevelOption> _readingLevelOptions = const [];
  bool _levelsEnabled = true;
  bool _isLoading = true;
  bool _comprehensionEnabled = false;
  String _sortBy = 'name';
  final DateTime _selectedPeriod = DateTime.now();
  String _periodType = 'week'; // 'week' or 'month'

  @override
  void initState() {
    super.initState();
    _loadReadingLevelOptions();
    _loadStudents();
    _loadComprehensionFlag();
  }

  Future<void> _loadComprehensionFlag() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      // Platform kill switch fetched alongside; never throws (fails open).
      final platformEnabledFuture =
          PlatformConfigService().isComprehensionRecordingEnabled();
      final doc =
          await _firebaseService.firestore.collection('schools').doc(schoolId).get();
      final platformEnabled = await platformEnabledFuture;
      if (!mounted || !doc.exists) return;
      final school = SchoolModel.fromFirestore(doc);
      setState(() {
        _comprehensionEnabled =
            platformEnabled && school.comprehensionRecordingSettings.enabled;
      });
    } catch (_) {
      // Default false; tile stays hidden.
    }
  }

  Future<void> _loadReadingLevelOptions({bool forceRefresh = false}) async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;

    try {
      final options = await _readingLevelService.loadSchoolLevels(
        schoolId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _readingLevelOptions = options;
        _levelsEnabled = options.isNotEmpty;
      });
    } catch (error) {
      debugPrint('Error loading class detail reading level options: $error');
    }
  }

  String _formatReadingLevel(String? value) {
    if (value == null || value.trim().isEmpty) return 'Not set';
    if (_readingLevelOptions.isEmpty) return value.trim();
    return _readingLevelService.formatLevelLabel(
      value,
      options: _readingLevelOptions,
    );
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
        if (_readingLevelOptions.isNotEmpty) {
          students.sort(
            (a, b) => _readingLevelService.compareLevels(
              a.currentReadingLevel,
              b.currentReadingLevel,
              options: _readingLevelOptions,
            ),
          );
        } else {
          students.sort((a, b) {
            final levelA = a.currentReadingLevel ?? 'ZZ';
            final levelB = b.currentReadingLevel ?? 'ZZ';
            return levelA.compareTo(levelB);
          });
        }
        break;
      case 'nights':
        students.sort((a, b) {
          final nightsA = a.stats?.totalReadingDays ?? 0;
          final nightsB = b.stats?.totalReadingDays ?? 0;
          return nightsB.compareTo(nightsA);
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
        final totalMinutes = studentLogs.fold<int>(
            0, (minutes, log) => minutes + log.minutesRead);
        final averageMinutes =
            studentLogs.isEmpty ? 0 : totalMinutes ~/ studentLogs.length;
        final booksRead = studentLogs.fold<int>(
            0, (bookCount, log) => bookCount + log.bookTitles.length);

        csvData.add([
          student.fullName,
          _formatReadingLevel(student.currentReadingLevel),
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
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Class Report - ${widget.classModel.name}',
        ),
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
            padding: const EdgeInsets.all(TeacherDimensions.paddingL),
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
                          horizontal: TeacherDimensions.paddingM,
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

          // Class settings — currently just the comprehension question.
          // Gated on the school toggle so we don't surface a setting that does
          // nothing; the section label makes it discoverable rather than a
          // blank row lost among the others.
          if (_comprehensionEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TeacherDimensions.paddingL,
                TeacherDimensions.paddingL,
                TeacherDimensions.paddingL,
                TeacherDimensions.paddingS,
              ),
              child: Text(
                'CLASS SETTINGS',
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            // A distinct, clearly-editable card (not a faint row) so the
            // comprehension prompt is easy to find and obviously changeable.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TeacherDimensions.paddingL,
                0,
                TeacherDimensions.paddingL,
                TeacherDimensions.paddingL,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusM),
                  border: Border.all(
                    color: AppColors.teacherPrimary.withValues(alpha: 0.35),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push(
                      '/teacher/class-comprehension-question/${widget.classModel.id}',
                      extra: {
                        'teacher': widget.teacher,
                        'classModel': widget.classModel,
                      },
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.all(TeacherDimensions.paddingL),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: AppColors.teacherPrimaryLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.mic_rounded,
                                    size: 20,
                                    color: AppColors.teacherPrimary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Comprehension question',
                                  style:
                                      TeacherTypography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.teacherPrimary,
                                  borderRadius: BorderRadius.circular(
                                      TeacherDimensions.radiusRound),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.edit_outlined,
                                        size: 14, color: AppColors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Edit',
                                      style:
                                          TeacherTypography.caption.copyWith(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '"${widget.classModel.comprehensionQuestion}"',
                            style: TeacherTypography.bodyMedium
                                .copyWith(color: AppColors.charcoal),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Students are asked this at the end of logging — '
                            'change it anytime.',
                            style: TeacherTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],

          // Period selector
          Container(
            color: AppColors.white,
            margin: const EdgeInsets.only(top: 1),
            padding: const EdgeInsets.all(TeacherDimensions.paddingL),
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
                const SizedBox(width: TeacherDimensions.paddingM),
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
                    if (_levelsEnabled)
                      DropdownMenuItem(
                        value: 'level',
                        child: Text('Sort by Level',
                            style: TeacherTypography.bodySmall),
                      ),
                    DropdownMenuItem(
                      value: 'nights',
                      child: Text('Sort by Total Nights',
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
              padding: const EdgeInsets.all(TeacherDimensions.paddingL),
              itemCount: _students.length,
              itemBuilder: (context, index) {
                final student = _students[index];
                return _StudentCard(
                  student: student,
                  classModel: widget.classModel,
                  teacher: widget.teacher,
                  periodStart: _getStartDate(),
                  periodEnd: _getEndDate(),
                  readingLevelFormatter: _formatReadingLevel,
                  levelsEnabled: _levelsEnabled,
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
  final String Function(String?) readingLevelFormatter;
  final bool levelsEnabled;

  const _StudentCard({
    required this.student,
    required this.classModel,
    required this.teacher,
    required this.periodStart,
    required this.periodEnd,
    required this.readingLevelFormatter,
    this.levelsEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TeacherDimensions.paddingM),
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
          padding: const EdgeInsets.all(TeacherDimensions.paddingL),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
            border: Border.all(color: AppColors.teacherBorder, width: 1),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: StreamBuilder<QuerySnapshot>(
            // Canonical path — logs and recordings live under the school
            // subcollection. The previous top-level `readingLogs` query read an
            // empty collection, so these per-student stats were always zero.
            stream: FirebaseService.instance.firestore
                .collection('schools')
                .doc(student.schoolId)
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
              final hasRecording = logs
                  .any((l) => (l.comprehensionAudioPath ?? '').isNotEmpty);
              final daysCompleted = logs.length;
              final totalMinutes = logs.fold<int>(
                  0, (minutes, log) => minutes + log.minutesRead);
              final averageMinutes =
                  logs.isEmpty ? 0 : totalMinutes ~/ logs.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(
                children: [
                  StudentAvatar.fromStudent(student, size: 50),
                  const SizedBox(width: TeacherDimensions.paddingM),
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
                            if (levelsEnabled) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: TeacherDimensions.paddingS,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.teacherPrimaryLight,
                                  borderRadius: BorderRadius.circular(
                                      TeacherDimensions.radiusRound),
                                ),
                                child: Text(
                                  'Level: ${readingLevelFormatter(student.currentReadingLevel)}',
                                  style: TeacherTypography.caption.copyWith(
                                    color: AppColors.teacherPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: TeacherDimensions.paddingS),
                            ],
                            if ((student.stats?.currentStreak ?? 0) > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: TeacherDimensions.paddingS,
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
                  // Mic badge when the student has a recording in this period
                  // (muted while it's still uploading).
                  if (hasRecording) ...[
                    const RecordingAffordance(),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.chevron_right,
                      size: 20, color: AppColors.textSecondary),
                ],
              ),

              const SizedBox(height: TeacherDimensions.paddingM),
              // Period stats (computed from the hoisted stream above).
              Row(
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
              ),
                ],
              );
            },
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
