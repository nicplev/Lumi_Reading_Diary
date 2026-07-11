import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/inline_stream_error.dart';
import 'package:go_router/go_router.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../services/firebase_service.dart';

/// Dashboard Recent Reading Card
///
/// Compact live feed of the class's most recent reading. Repeated sessions of
/// the same book by the same student on the same day are grouped into one row.
class DashboardRecentReadingCard extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;
  final List<StudentModel> students;
  final UserModel teacher;
  final VoidCallback? onViewAll;

  const DashboardRecentReadingCard({
    super.key,
    required this.classModel,
    required this.schoolId,
    required this.students,
    required this.teacher,
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
    // Fetch more than we show so grouping is accurate, then show ~5 groups.
    _recentLogsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .orderBy('date', descending: true)
        .limit(15)
        .snapshots();
  }

  /// Groups same-student / same-book / same-day logs into one entry.
  List<List<ReadingLogModel>> _group(List<ReadingLogModel> logs) {
    String key(ReadingLogModel l) {
      final day = '${l.date.year}-${l.date.month}-${l.date.day}';
      final book = l.bookTitles.isNotEmpty ? l.bookTitles.first : '__free__';
      return '${l.studentId}::$day::$book';
    }

    final groups = <List<ReadingLogModel>>[];
    for (final log in logs) {
      List<ReadingLogModel>? target;
      for (final g in groups) {
        if (key(g.first) == key(log)) {
          target = g;
          break;
        }
      }
      if (target != null) {
        target.add(log);
      } else {
        groups.add([log]);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final studentMap = {
      for (final s in widget.students) s.id: s,
    };

    return StreamBuilder<QuerySnapshot>(
      stream: _recentLogsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const InlineStreamError(message: "Couldn't load recent reading.");
        }
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        if (logs.isEmpty && !snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final groups = _group(logs).take(5).toList();

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
                  Text('Recent Reading', style: LumiType.subhead),
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
              if (groups.isEmpty)
                _buildEmptyState()
              else
                ...groups.asMap().entries.map((entry) {
                  final index = entry.key;
                  final group = entry.value;
                  final student = studentMap[group.first.studentId];
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(height: 1, color: LumiTokens.rule),
                      _RecentLogRow(
                        group: group,
                        studentName: student?.firstNameWithLastInitial ?? '?',
                        initials: _getInitials(student),
                        characterId: student?.displayCharacterId,
                        onTap: student == null
                            ? null
                            : () => context.push(
                                  '/teacher/student-detail/${student.id}',
                                  extra: {
                                    'teacher': widget.teacher,
                                    'student': student,
                                    'classModel': widget.classModel,
                                  },
                                ),
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text('No reading logged yet', style: LumiType.caption),
      ),
    );
  }

  String _getInitials(StudentModel? student) {
    if (student == null) return '?';
    final first = student.firstName.isNotEmpty ? student.firstName[0] : '';
    final last = student.lastName.isNotEmpty ? student.lastName[0] : '';
    return '$first$last'.toUpperCase();
  }
}

class _RecentLogRow extends StatelessWidget {
  final List<ReadingLogModel> group;
  final String studentName;
  final String initials;
  final String? characterId;
  final VoidCallback? onTap;

  const _RecentLogRow({
    required this.group,
    required this.studentName,
    required this.initials,
    this.characterId,
    this.onTap,
  });

  static const _avatarColors = [
    LumiTokens.tintRed,
    LumiTokens.tintBlue,
    LumiTokens.tintGreen,
    LumiTokens.tintYellow,
    LumiTokens.tintOrange,
  ];

  String _relativeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final rep = group.first;
    final bookTitle =
        rep.bookTitles.isNotEmpty ? rep.bookTitles.first : 'Free reading';
    final totalMinutes = group.fold<int>(0, (a, l) => a + l.minutesRead);
    final sessions = group.length;
    final colorIndex = initials.hashCode.abs() % _avatarColors.length;
    final avatarBg = _avatarColors[colorIndex];

    final meta = sessions > 1
        ? '$bookTitle · $sessions sessions · $totalMinutes min'
        : '$bookTitle · $totalMinutes min';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            StudentAvatar(
              characterId: characterId,
              initial: initials,
              avatarColor: avatarBg,
              size: 32,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: studentName,
                          style: LumiType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: LumiTokens.ink,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${_relativeDate(rep.date)}',
                          style:
                              LumiType.caption.copyWith(color: LumiTokens.muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: LumiType.caption.copyWith(color: LumiTokens.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (rep.childFeeling != null) ...[
              const SizedBox(width: 8),
              Image.asset(
                'assets/blobs/blob-${rep.childFeeling!.name}.png',
                width: 20,
                height: 20,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
