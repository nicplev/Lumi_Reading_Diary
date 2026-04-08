import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../services/firebase_service.dart';

/// Dashboard Recent Reading Card
///
/// Compact live feed showing the 5 most recent reading logs for the class.
/// Reuses the shared students list from the dashboard to avoid duplicate
/// Firestore reads.
class DashboardRecentReadingCard extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;
  final List<StudentModel> students;
  final VoidCallback? onViewAll;

  const DashboardRecentReadingCard({
    super.key,
    required this.classModel,
    required this.schoolId,
    required this.students,
    this.onViewAll,
  });

  @override
  State<DashboardRecentReadingCard> createState() =>
      _DashboardRecentReadingCardState();
}

class _DashboardRecentReadingCardState
    extends State<DashboardRecentReadingCard> {
  late Stream<QuerySnapshot> _recentLogsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(DashboardRecentReadingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
    }
  }

  void _initStream() {
    _recentLogsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .orderBy('date', descending: true)
        .limit(5)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final studentMap = {
      for (final s in widget.students) s.id: s,
    };

    return StreamBuilder<QuerySnapshot>(
      stream: _recentLogsStream,
      builder: (context, snapshot) {
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        if (logs.isEmpty && !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius:
                BorderRadius.circular(TeacherDimensions.radiusXL),
            border: Border.all(color: AppColors.teacherBorder),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.04),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Reading',
                    style: TeacherTypography.sectionHeader,
                  ),
                  if (widget.onViewAll != null)
                    GestureDetector(
                      onTap: widget.onViewAll,
                      child: Text(
                        'View all',
                        style: TeacherTypography.bodySmall.copyWith(
                          color: AppColors.teacherPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Log list or empty state
              if (logs.isEmpty)
                _buildEmptyState()
              else
                ...logs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final log = entry.value;
                  final student = studentMap[log.studentId];
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(
                          height: 1,
                          color: AppColors.teacherBorder
                              .withValues(alpha: 0.5),
                        ),
                      _RecentLogRow(
                        log: log,
                        studentName: student?.firstName ?? '?',
                        initials: _getInitials(student),
                      ),
                    ],
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 28,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'No reading logged yet',
              style: TeacherTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(StudentModel? student) {
    if (student == null) return '?';
    final first =
        student.firstName.isNotEmpty ? student.firstName[0] : '';
    final last =
        student.lastName.isNotEmpty ? student.lastName[0] : '';
    return '$first$last'.toUpperCase();
  }
}

class _RecentLogRow extends StatelessWidget {
  final ReadingLogModel log;
  final String studentName;
  final String initials;

  const _RecentLogRow({
    required this.log,
    required this.studentName,
    required this.initials,
  });

  static const _avatarColors = [
    Color(0xFFF8BBD0), // pink
    Color(0xFFBBDEFB), // blue
    Color(0xFFC8E6C9), // green
    Color(0xFFFFE0B2), // orange
    Color(0xFFE1BEE7), // purple
    Color(0xFFB2EBF2), // cyan
  ];

  @override
  Widget build(BuildContext context) {
    final bookTitle = log.bookTitles.isNotEmpty
        ? log.bookTitles.first
        : 'Free reading';
    final colorIndex = initials.hashCode.abs() % _avatarColors.length;
    final avatarBg = _avatarColors[colorIndex];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: avatarBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                initials,
                style: TeacherTypography.caption.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name
          SizedBox(
            width: 64,
            child: Text(
              studentName,
              style: TeacherTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Book title
          Expanded(
            child: Text(
              bookTitle,
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Minutes
          Text(
            '${log.minutesRead}m',
            style: TeacherTypography.bodySmall.copyWith(
              color: AppColors.teacherPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          // Feeling blob
          if (log.childFeeling != null) ...[
            const SizedBox(width: 6),
            Image.asset(
              'assets/blobs/blob-${log.childFeeling!.name}.png',
              width: 18,
              height: 18,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}
