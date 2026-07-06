import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/inline_stream_error.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/student_avatar.dart';
import '../../../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../services/firebase_service.dart';

/// Dashboard widget: the parents who've replied and are waiting on the teacher.
///
/// Surfaces reading logs whose newest comment is from a parent and hasn't been
/// seen by this teacher yet, so conversations don't go stale. Tapping a row
/// opens that log's comment thread (which marks it read).
class DashboardUnreadCommentsCard extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;
  final List<StudentModel> students;

  const DashboardUnreadCommentsCard({
    super.key,
    required this.classModel,
    required this.schoolId,
    required this.students,
  });

  @override
  State<DashboardUnreadCommentsCard> createState() =>
      _DashboardUnreadCommentsCardState();
}

class _DashboardUnreadCommentsCardState
    extends State<DashboardUnreadCommentsCard> {
  late Stream<QuerySnapshot> _logsStream;

  static const _avatarColors = [
    LumiTokens.tintRed,
    LumiTokens.tintBlue,
    LumiTokens.tintGreen,
    LumiTokens.tintYellow,
    LumiTokens.tintOrange,
  ];

  @override
  void initState() {
    super.initState();
    _initStream();
  }

  @override
  void didUpdateWidget(DashboardUnreadCommentsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
    }
  }

  void _initStream() {
    // Order by lastCommentAt (not log date): a parent can reply on an OLDER
    // log, and ordering by log date meant those replies fell outside the window
    // for a busy class (80 logs ≈ under a day) — the card showed "Up to date"
    // while the teacher missed replies. Ordering by comment time surfaces the
    // most recently-commented logs regardless of log age. `orderBy` excludes
    // logs with no comment (null lastCommentAt), so this only ever returns
    // commented logs, which we then filter to unread-by-teacher client-side.
    // Needs the (classId ASC, lastCommentAt DESC) composite index.
    _logsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .orderBy('lastCommentAt', descending: true)
        .limit(80)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final studentMap = {for (final s in widget.students) s.id: s};

    return StreamBuilder<QuerySnapshot>(
      stream: _logsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const InlineStreamError(message: "Couldn't load parent comments.");
        }
        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final unread = logs
            .where((l) => uid.isNotEmpty && l.hasUnreadFor(uid, 'teacher'))
            .toList()
          ..sort((a, b) => b.lastCommentAt!.compareTo(a.lastCommentAt!));

        final shown = unread.take(5).toList();

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
                children: [
                  Text('Parent Comments', style: LumiType.subhead),
                  const SizedBox(width: 8),
                  if (unread.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: LumiTokens.green,
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                      child: Text(
                        '${unread.length}',
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.paper,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    unread.isEmpty ? 'Up to date' : 'Awaiting reply',
                    style: LumiType.caption,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (shown.isEmpty)
                _buildEmptyState()
              else
                ...shown.asMap().entries.map((entry) {
                  final index = entry.key;
                  final log = entry.value;
                  final student = studentMap[log.studentId];
                  return Column(
                    children: [
                      if (index > 0)
                        Divider(height: 1, color: LumiTokens.rule),
                      _UnreadCommentRow(
                        log: log,
                        student: student,
                        avatarColor: _avatarColors[
                            (student?.id.hashCode ?? index).abs() %
                                _avatarColors.length],
                      ),
                    ],
                  );
                }),
              if (unread.length > shown.length) ...[
                const SizedBox(height: 8),
                Text(
                  '+${unread.length - shown.length} more waiting',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Row(
      children: [
        Icon(Icons.mark_chat_read_rounded,
            size: 16, color: LumiTokens.green.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text('No parent replies waiting', style: LumiType.caption),
      ],
    );
  }
}

class _UnreadCommentRow extends StatelessWidget {
  final ReadingLogModel log;
  final StudentModel? student;
  final Color avatarColor;

  const _UnreadCommentRow({
    required this.log,
    required this.student,
    required this.avatarColor,
  });

  String _initials(StudentModel? s) {
    if (s == null) return '?';
    final f = s.firstName.isNotEmpty ? s.firstName[0] : '';
    final l = s.lastName.isNotEmpty ? s.lastName[0] : '';
    return '$f$l'.toUpperCase();
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}';
  }

  @override
  Widget build(BuildContext context) {
    final name = student?.firstName ?? 'Unknown';
    return InkWell(
      onTap: student == null
          ? null
          : () => openTeacherCommentsSheet(
                context,
                log: log,
                studentName: name,
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StudentAvatar(
              characterId: student?.displayCharacterId,
              initial: _initials(student),
              avatarColor: avatarColor,
              size: 34,
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
                          text: name,
                          style: LumiType.caption.copyWith(
                            fontWeight: FontWeight.w700,
                            color: LumiTokens.ink,
                          ),
                        ),
                        TextSpan(
                          text: '  ·  ${_relativeTime(log.lastCommentAt)}',
                          style: LumiType.caption
                              .copyWith(color: LumiTokens.muted),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    log.lastCommentPreview ?? 'New comment',
                    style: LumiType.caption.copyWith(color: LumiTokens.ink),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: LumiTokens.green,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
