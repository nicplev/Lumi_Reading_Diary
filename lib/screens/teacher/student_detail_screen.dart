import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_stat_card.dart';
import '../../core/widgets/lumi/teacher_book_assignment_card.dart';
import '../../core/widgets/lumi/teacher_student_list_item.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/class_model.dart';
import '../../data/models/allocation_model.dart';
import '../../services/firebase_service.dart';

/// Student Detail Screen
///
/// Shows student profile, stats, assigned books, and latest parent comment.
/// Per spec: avatar header, 2-col stats, assigned books list, parent comment.
class StudentDetailScreen extends StatefulWidget {
  final UserModel teacher;
  final StudentModel student;
  final ClassModel? classModel;

  const StudentDetailScreen({
    super.key,
    required this.teacher,
    required this.student,
    this.classModel,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final Map<String, Future<String>> _parentNameFutures = {};

  Future<void> _openAssignFlow() async {
    try {
      var classModel = widget.classModel;
      if (classModel == null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class not found for this student'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        classModel = ClassModel.fromFirestore(classDoc);
      }

      if (!mounted) return;
      await context.push(
        '/teacher/allocation',
        extra: {
          'teacher': widget.teacher,
          'selectedClass': classModel,
          'preselectedStudentId': widget.student.id,
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open assignment flow'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _openIsbnScannerFlow() async {
    try {
      var classModel = widget.classModel;
      if (classModel == null) {
        final classDoc = await _firebaseService.firestore
            .collection('schools')
            .doc(widget.student.schoolId)
            .collection('classes')
            .doc(widget.student.classId)
            .get();
        if (!classDoc.exists) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Class not found for this student'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }
        classModel = ClassModel.fromFirestore(classDoc);
      }

      if (!mounted) return;
      final result = await context.push(
        '/teacher/isbn-scanner',
        extra: {
          'teacher': widget.teacher,
          'student': widget.student,
          'classModel': classModel,
        },
      );

      if (!mounted || result == null) return;
      if (result is! Map<String, dynamic>) return;

      final scannedCount = (result['scannedCount'] as num?)?.toInt() ?? 0;
      final totalAssigned =
          (result['totalAssignedBooks'] as num?)?.toInt() ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            scannedCount > 0
                ? 'Scanned $scannedCount book(s). $totalAssigned assigned this week.'
                : 'No ISBN scans captured.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open ISBN scanner'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<String> _getParentName(String? parentId) {
    if (parentId == null || parentId.isEmpty) {
      return Future.value('Parent');
    }
    return _parentNameFutures.putIfAbsent(parentId, () async {
      final schoolRef = _firebaseService.firestore
          .collection('schools')
          .doc(widget.student.schoolId);

      final parentDoc =
          await schoolRef.collection('parents').doc(parentId).get();
      if (parentDoc.exists) {
        final data = parentDoc.data() ?? {};
        final name = data['fullName'] as String?;
        if (name != null && name.trim().isNotEmpty) return name;
      }

      final userDoc = await schoolRef.collection('users').doc(parentId).get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        final name = data['fullName'] as String?;
        if (name != null && name.trim().isNotEmpty) return name;
      }

      return 'Parent';
    });
  }

  List<_ReadingLogSnapshot> _toReadingLogs(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final dateTimestamp = data['date'] as Timestamp?;
      final commentSelections = data['parentCommentSelections'];
      return _ReadingLogSnapshot(
        id: doc.id,
        date: dateTimestamp?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0),
        allocationId: data['allocationId'] as String?,
        bookTitles: List<String>.from(data['bookTitles'] ?? const []),
        status: (data['status'] as String?) ?? '',
        minutesRead: (data['minutesRead'] as num?)?.toInt() ?? 0,
        targetMinutes: (data['targetMinutes'] as num?)?.toInt() ?? 0,
        parentId: data['parentId'] as String?,
        parentComment: (data['parentComment'] as String?)?.trim(),
        parentCommentSelections: commentSelections is List
            ? commentSelections.whereType<String>().toList()
            : const [],
        parentCommentFreeText:
            (data['parentCommentFreeText'] as String?)?.trim(),
        childFeeling: data['childFeeling'] as String?,
      );
    }).toList();
  }

  List<_AssignedBookViewData> _mapAssignedBooks(
    List<AllocationModel> allocations,
    List<_ReadingLogSnapshot> logs,
  ) {
    final now = DateTime.now();
    final seen = <String>{};
    final results = <_AssignedBookViewData>[];

    for (final allocation in allocations) {
      final withinWindow = !allocation.startDate.isAfter(now) &&
          !allocation.endDate.isBefore(now);
      final appliesToStudent = allocation.isForWholeClass ||
          allocation.studentIds.contains(widget.student.id);
      if (!withinWindow || !appliesToStudent) continue;

      if (allocation.type == AllocationType.byTitle &&
          allocation.bookTitles != null &&
          allocation.bookTitles!.isNotEmpty) {
        for (final title in allocation.bookTitles!) {
          final dedupeKey = 'title:${title.trim().toLowerCase()}';
          if (seen.contains(dedupeKey)) continue;
          seen.add(dedupeKey);
          final status = _deriveStatusForTitle(allocation, logs, title);
          final type = _inferBookType(allocation);
          results.add(
            _AssignedBookViewData(
              title: title,
              subtitle:
                  '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
              bookType: type,
              status: status,
              coverGradient: _coverGradient(type, title),
            ),
          );
        }
        continue;
      }

      final dedupeKey = 'allocation:${allocation.id}';
      if (seen.contains(dedupeKey)) continue;
      seen.add(dedupeKey);
      final status = _deriveStatusForAllocation(allocation, logs);
      final type = _inferBookType(allocation);
      results.add(
        _AssignedBookViewData(
          title: _allocationTitle(allocation),
          subtitle:
              '${allocation.targetMinutes} min • ${_cadenceLabel(allocation.cadence)}',
          bookType: type,
          status: status,
          coverGradient: _coverGradient(type, allocation.id),
        ),
      );
    }

    return results;
  }

  String _deriveStatusForTitle(
    AllocationModel allocation,
    List<_ReadingLogSnapshot> logs,
    String title,
  ) {
    final titleKey = title.trim().toLowerCase();
    final matching = logs.where((log) {
      final inWindow = !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
      if (!inWindow) return false;
      if (log.allocationId == allocation.id) return true;
      return log.bookTitles
          .any((book) => book.trim().toLowerCase() == titleKey);
    }).toList();

    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _deriveStatusForAllocation(
    AllocationModel allocation,
    List<_ReadingLogSnapshot> logs,
  ) {
    final matching = logs.where((log) {
      if (log.allocationId != allocation.id) return false;
      return !log.date.isBefore(allocation.startDate) &&
          !log.date.isAfter(allocation.endDate.add(const Duration(days: 1)));
    }).toList();
    if (matching.isEmpty) return 'new';
    final hasCompletion = matching.any((log) =>
        log.status == 'completed' || log.minutesRead >= log.targetMinutes);
    return hasCompletion ? 'completed' : 'in_progress';
  }

  String _allocationTitle(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel) {
      if (allocation.levelStart != null && allocation.levelEnd != null) {
        return 'Level ${allocation.levelStart}-${allocation.levelEnd} Reading';
      }
      if (allocation.levelStart != null) {
        return 'Level ${allocation.levelStart} Reading';
      }
    }
    if (allocation.type == AllocationType.freeChoice) {
      return 'Free Choice Reading';
    }
    return 'Reading Allocation';
  }

  String _cadenceLabel(AllocationCadence cadence) {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Daily';
      case AllocationCadence.weekly:
        return 'Weekly';
      case AllocationCadence.fortnightly:
        return 'Fortnightly';
      case AllocationCadence.custom:
        return 'Custom';
    }
  }

  String _inferBookType(AllocationModel allocation) {
    if (allocation.type == AllocationType.byLevel ||
        allocation.levelStart != null) {
      return 'decodable';
    }
    return 'library';
  }

  List<Color> _coverGradient(String type, String seed) {
    if (type == 'decodable') {
      const palettes = <List<Color>>[
        [AppColors.levelCVC, Color(0xFFEF5350)],
        [AppColors.levelDigraphs, Color(0xFFFF9800)],
        [AppColors.levelBlends, Color(0xFFFDD835)],
        [AppColors.levelCVCE, Color(0xFF66BB6A)],
        [AppColors.levelVowelTeams, Color(0xFF42A5F5)],
        [AppColors.levelRControlled, Color(0xFFAB47BC)],
      ];
      final index = seed.hashCode.abs() % palettes.length;
      return palettes[index];
    }
    return const [Color(0xFF81C784), Color(0xFF388E3C)];
  }

  _LatestParentCommentViewData? _latestParentComment(
    List<_ReadingLogSnapshot> logs,
  ) {
    for (final log in logs) {
      final hasComment = (log.parentComment?.isNotEmpty ?? false) ||
          log.parentCommentSelections.isNotEmpty ||
          (log.parentCommentFreeText?.isNotEmpty ?? false);
      if (!hasComment) continue;

      final text = _composeCommentText(log);
      if (text.isEmpty) continue;

      return _LatestParentCommentViewData(
        parentId: log.parentId,
        commentText: text,
        date: log.date,
        selections: log.parentCommentSelections,
        starRating: _starRatingFromFeeling(log.childFeeling),
      );
    }
    return null;
  }

  String _composeCommentText(_ReadingLogSnapshot log) {
    final chips = log.parentCommentSelections.join('. ');
    final freeText = log.parentCommentFreeText?.trim() ?? '';
    final structured =
        [chips, freeText].where((value) => value.isNotEmpty).join('. ').trim();
    if (structured.isNotEmpty) return structured;
    return log.parentComment?.trim() ?? '';
  }

  int? _starRatingFromFeeling(String? childFeeling) {
    switch (childFeeling) {
      case 'hard':
        return 1;
      case 'tricky':
        return 2;
      case 'okay':
        return 3;
      case 'good':
        return 4;
      case 'great':
        return 5;
      default:
        return null;
    }
  }

  String _formatCommentDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (dateOnly == today) return 'Today';
    if (dateOnly == yesterday) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Student Detail',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student header
            _buildStudentHeader(),
            const SizedBox(height: 20),

            // Stats cards (2-column)
            _buildStatsRow(),
            const SizedBox(height: 24),

            // Assigned Books section
            _buildAssignedBooksSection(),
            const SizedBox(height: 24),

            // Latest Parent Comment
            _buildParentCommentSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentHeader() {
    final fullName = '${widget.student.firstName} ${widget.student.lastName}';

    return Row(
      children: [
        CircleAvatar(
          radius: TeacherDimensions.avatarM / 2,
          backgroundColor: TeacherStudentListItem.colorForName(fullName),
          child: Text(
            widget.student.firstName[0].toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName, style: TeacherTypography.h2),
              const SizedBox(height: 4),
              if (widget.student.currentReadingLevel != null)
                Text(
                  'Level ${widget.student.currentReadingLevel}',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: TeacherStatCard(
            icon: Icons.local_fire_department,
            iconColor: AppColors.warmOrange,
            iconBgColor: AppColors.warmOrange.withValues(alpha: 0.15),
            value: '${widget.student.stats?.currentStreak ?? 0}',
            label: 'Day Streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TeacherStatCard(
            icon: Icons.nights_stay,
            iconColor: AppColors.teacherPrimary,
            iconBgColor: AppColors.teacherPrimaryLight,
            value: '${widget.student.stats?.totalReadingDays ?? 0}',
            label: 'Total Nights',
          ),
        ),
      ],
    );
  }

  Widget _buildAssignedBooksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Assigned Books', style: TeacherTypography.h3),
            const Spacer(),
            TextButton.icon(
              onPressed: _openIsbnScannerFlow,
              icon: Icon(Icons.qr_code_scanner,
                  size: 18, color: AppColors.teacherPrimary),
              label: Text(
                'Scan',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _openAssignFlow,
              icon: Icon(Icons.add, size: 18, color: AppColors.teacherPrimary),
              label: Text(
                'Assign',
                style: TeacherTypography.bodyMedium.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.student.schoolId)
              .collection('allocations')
              .where('classId', isEqualTo: widget.student.classId)
              .where('isActive', isEqualTo: true)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, allocationSnapshot) {
            if (allocationSnapshot.hasError) {
              return _buildSectionInfoCard(
                'Could not load assigned books',
                isError: true,
              );
            }
            if (!allocationSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final allocations = allocationSnapshot.data!.docs
                .map((doc) => AllocationModel.fromFirestore(doc))
                .toList();

            return StreamBuilder<QuerySnapshot>(
              stream: _firebaseService.firestore
                  .collection('schools')
                  .doc(widget.student.schoolId)
                  .collection('readingLogs')
                  .where('studentId', isEqualTo: widget.student.id)
                  .orderBy('date', descending: true)
                  .limit(200)
                  .snapshots(),
              builder: (context, logSnapshot) {
                if (logSnapshot.hasError) {
                  return _buildSectionInfoCard(
                    'Could not load reading progress',
                    isError: true,
                  );
                }
                if (!logSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final logs = _toReadingLogs(logSnapshot.data!);
                final books = _mapAssignedBooks(allocations, logs);

                if (books.isEmpty) {
                  return _buildSectionInfoCard(
                    'No active assigned books for this student yet.',
                  );
                }

                return Column(
                  children: books.map((book) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TeacherBookAssignmentCard(
                        title: book.title,
                        subtitle: book.subtitle,
                        coverGradient: book.coverGradient,
                        bookType: book.bookType,
                        status: book.status,
                      ),
                    );
                  }).toList(),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildParentCommentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Latest Parent Comment', style: TeacherTypography.h3),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot>(
          stream: _firebaseService.firestore
              .collection('schools')
              .doc(widget.student.schoolId)
              .collection('readingLogs')
              .where('studentId', isEqualTo: widget.student.id)
              .orderBy('date', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildSectionInfoCard(
                'Could not load parent comments',
                isError: true,
              );
            }

            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final logs = _toReadingLogs(snapshot.data!);
            final latest = _latestParentComment(logs);
            if (latest == null) {
              return _buildSectionInfoCard('No parent comments yet.');
            }

            return FutureBuilder<String>(
              future: _getParentName(latest.parentId),
              builder: (context, parentSnapshot) {
                final parentName = parentSnapshot.data ?? 'Parent';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusL),
                    boxShadow: TeacherDimensions.cardShadow,
                    border: const Border(
                      left: BorderSide(
                        color: AppColors.teacherPrimary,
                        width: 4,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"${latest.commentText}"',
                        style: TeacherTypography.bodyMedium.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      if (latest.selections.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: latest.selections.map((chip) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.teacherPrimaryLight,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                chip,
                                style: TeacherTypography.caption.copyWith(
                                  color: AppColors.teacherPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (latest.starRating != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: List.generate(5, (index) {
                            final isFilled = index < latest.starRating!;
                            return Icon(
                              isFilled ? Icons.star : Icons.star_border,
                              size: 16,
                              color: AppColors.warmOrange,
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '— $parentName • ${_formatCommentDate(latest.date)}',
                        style: TeacherTypography.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionInfoCard(String message, {bool isError = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Text(
        message,
        style: TeacherTypography.bodyMedium.copyWith(
          color: isError ? AppColors.error : AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _AssignedBookViewData {
  final String title;
  final String subtitle;
  final String bookType;
  final String status;
  final List<Color> coverGradient;

  const _AssignedBookViewData({
    required this.title,
    required this.subtitle,
    required this.bookType,
    required this.status,
    required this.coverGradient,
  });
}

class _ReadingLogSnapshot {
  final String id;
  final DateTime date;
  final String? allocationId;
  final List<String> bookTitles;
  final String status;
  final int minutesRead;
  final int targetMinutes;
  final String? parentId;
  final String? parentComment;
  final List<String> parentCommentSelections;
  final String? parentCommentFreeText;
  final String? childFeeling;

  const _ReadingLogSnapshot({
    required this.id,
    required this.date,
    required this.allocationId,
    required this.bookTitles,
    required this.status,
    required this.minutesRead,
    required this.targetMinutes,
    required this.parentId,
    required this.parentComment,
    required this.parentCommentSelections,
    required this.parentCommentFreeText,
    required this.childFeeling,
  });
}

class _LatestParentCommentViewData {
  final String? parentId;
  final String commentText;
  final DateTime date;
  final List<String> selections;
  final int? starRating;

  const _LatestParentCommentViewData({
    required this.parentId,
    required this.commentText,
    required this.date,
    required this.selections,
    required this.starRating,
  });
}
