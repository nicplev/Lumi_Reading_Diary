import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/teacher_constants.dart';
import '../../../core/utils/image_decode.dart';
import '../../../data/models/student_model.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'reading_log_snapshot.dart';
import 'section_info_card.dart';

/// "Latest Parent Comment" card on the teacher student-detail screen.
///
/// Prefers the server-denormalised `latestParentComment` field on the student
/// doc (one doc read, C7 — includes the parent name and unread state). Falls
/// back to the former 50-log live scan while the aggregate hasn't been
/// backfilled for this student. Remove the fallback one release after the
/// backfill has run in production. Opening the thread stays with the parent
/// screen via [onOpenLogComments].
class ParentCommentSection extends ConsumerStatefulWidget {
  final StudentDetailLookup lookup;
  final FirebaseFirestore firestore;
  final void Function(ReadingLogSnapshot snap) onOpenLogComments;

  const ParentCommentSection({
    super.key,
    required this.lookup,
    required this.firestore,
    required this.onOpenLogComments,
  });

  @override
  ConsumerState<ParentCommentSection> createState() =>
      _ParentCommentSectionState();
}

class _ParentCommentSectionState extends ConsumerState<ParentCommentSection> {
  final Map<String, Future<String>> _parentNameFutures = {};

  @override
  void didUpdateWidget(covariant ParentCommentSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lookup != widget.lookup) {
      _parentNameFutures.clear();
    }
  }

  Future<String> _getParentName(String? parentId) {
    if (parentId == null || parentId.isEmpty) {
      return Future.value('Parent');
    }
    return _parentNameFutures.putIfAbsent(parentId, () async {
      final schoolRef = widget.firestore
          .collection('schools')
          .doc(widget.lookup.schoolId);

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

  /// Minimal snapshot for opening the comment thread from the aggregate —
  /// the sheet needs ids, date and the denormalised thread state.
  ReadingLogSnapshot _snapshotFromAggregate(LatestParentCommentData agg) {
    return ReadingLogSnapshot(
      id: agg.logId,
      date: agg.date,
      createdAt: agg.date,
      allocationId: null,
      bookTitles: const [],
      status: 'completed',
      minutesRead: 0,
      targetMinutes: 0,
      parentId: agg.parentId,
      parentComment: null,
      parentCommentSelections: agg.presetChips,
      parentCommentFreeText: agg.freeText,
      childFeeling: agg.feeling,
      lastCommentAt: agg.lastCommentAt,
      lastCommentByRole: agg.lastCommentByRole,
      commentsViewedAt: agg.commentsViewedAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(studentDocProvider(widget.lookup)).value;

    Widget body;
    if (student != null && student.hasLatestParentCommentField) {
      final agg = student.latestParentComment;
      if (agg == null) {
        body = const _NoCommentsCard();
      } else {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        body = _CommentCard(
          feeling: agg.feeling,
          selections: agg.presetChips,
          commentText: agg.freeText,
          parentName: agg.parentName,
          date: agg.date,
          unread: agg.hasUnreadForTeacher(uid),
          onTap: () => widget.onOpenLogComments(_snapshotFromAggregate(agg)),
        );
      }
    } else {
      body = _buildFromLogStream();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Latest Parent Comment', style: LumiType.subhead),
        const SizedBox(height: 8),
        body,
      ],
    );
  }

  /// Pre-backfill fallback: the former 50-log live scan.
  Widget _buildFromLogStream() {
    final snapshot = ref.watch(studentCommentLogsProvider(widget.lookup));
    return snapshot.when(
      error: (_, __) => const SectionInfoCard(
        'Could not load parent comments',
        isError: true,
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      ),
      data: (querySnapshot) {
        final logs = toReadingLogSnapshots(querySnapshot);
        final latest = latestParentComment(logs);
        if (latest == null) {
          return const _NoCommentsCard();
        }

        return FutureBuilder<String>(
          future: _getParentName(latest.parentId),
          builder: (context, parentSnapshot) {
            final parentName = parentSnapshot.data ?? 'Parent';
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            return _CommentCard(
              feeling: latest.feeling,
              selections: latest.selections,
              commentText: latest.commentText,
              parentName: parentName,
              date: latest.date,
              unread: latest.log.hasUnreadForTeacher(uid),
              onTap: () => widget.onOpenLogComments(latest.log),
            );
          },
        );
      },
    );
  }
}

class _NoCommentsCard extends StatelessWidget {
  const _NoCommentsCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Row(
          children: [
            Container(width: 4, height: 48, color: LumiTokens.rule),
            const SizedBox(width: 12),
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 16,
              color: LumiTokens.muted.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Text(
              'No parent comments yet',
              style: LumiType.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final String? feeling;
  final List<String> selections;
  final String commentText;
  final String parentName;
  final DateTime date;
  final bool unread;
  final VoidCallback onTap;

  const _CommentCard({
    required this.feeling,
    required this.selections,
    required this.commentText,
    required this.parentName,
    required this.date,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          border: Border.all(color: LumiTokens.rule),
          // Left accent via a gradient trick won't work with
          // Border.all, so we overlay it below.
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Comment icon — green only when unread for the teacher
              // (green = needs attention), neutral once read.
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: unread
                      ? LumiTokens.tintGreen
                      : LumiTokens.muted.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 14,
                  color: unread ? LumiTokens.green : LumiTokens.muted,
                ),
              ),
              const SizedBox(width: 10),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Child's feeling — its own line, distinct from
                    // the parent's topic chips below.
                    if (feeling != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/blobs/blob-$feeling.png',
                            width: 22,
                            cacheWidth: decodeCacheSize(context, 22),
                            height: 22,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            feeling![0].toUpperCase() + feeling!.substring(1),
                            style: LumiType.caption.copyWith(
                              color: LumiTokens.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (selections.isNotEmpty || commentText.isNotEmpty)
                        const SizedBox(height: 8),
                    ],
                    // Parent's topic selections — up to 3, wrap cleanly.
                    if (selections.isNotEmpty) ...[
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selections.map((chip) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: LumiTokens.muted.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusSmall),
                            ),
                            child: Text(
                              chip,
                              style: LumiType.caption.copyWith(
                                color: LumiTokens.ink,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (commentText.isNotEmpty) const SizedBox(height: 8),
                    ],
                    // Free-text comment — wraps, but capped to a short
                    // preview (the row taps through to the full thread).
                    if (commentText.isNotEmpty) ...[
                      Text(
                        commentText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: LumiType.body.copyWith(
                          fontStyle: FontStyle.italic,
                          color: LumiTokens.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '— $parentName · ${formatCommentDate(date)}',
                            style: LumiType.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: LumiTokens.tintGreen,
                              borderRadius: BorderRadius.circular(
                                  LumiTokens.radiusPill),
                            ),
                            child: Text(
                              'New',
                              style: LumiType.caption.copyWith(
                                color: LumiTokens.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
