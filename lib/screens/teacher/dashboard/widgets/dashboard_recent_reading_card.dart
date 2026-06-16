import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
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
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            border: Border.all(color: LumiTokens.rule),
            boxShadow: LumiTokens.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Recent Reading',
                    style: LumiType.subhead,
                  ),
                  if (widget.onViewAll != null)
                    GestureDetector(
                      onTap: widget.onViewAll,
                      child: Text(
                        'View all',
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.blue,
                          fontWeight: FontWeight.w700,
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
                          color: LumiTokens.rule,
                        ),
                      _RecentLogRow(
                        log: log,
                        studentName: student?.firstName ?? '?',
                        initials: _getInitials(student),
                        characterId: student?.characterId,
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
              color: LumiTokens.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 8),
            Text(
              'No reading logged yet',
              style: LumiType.caption,
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
  final String? characterId;

  const _RecentLogRow({
    required this.log,
    required this.studentName,
    required this.initials,
    this.characterId,
  });

  static const _avatarColors = [
    LumiTokens.tintRed,
    LumiTokens.tintBlue,
    LumiTokens.tintGreen,
    LumiTokens.tintYellow,
    LumiTokens.tintOrange,
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
          StudentAvatar(
            characterId: characterId,
            initial: initials,
            avatarColor: avatarBg,
            size: 30,
          ),
          const SizedBox(width: 10),
          // Name
          SizedBox(
            width: 64,
            child: Text(
              studentName,
              style: LumiType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: LumiTokens.ink,
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
              style: LumiType.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Minutes
          Text(
            '${log.minutesRead}m',
            style: LumiType.caption.copyWith(
              color: LumiTokens.blue,
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
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }
}
