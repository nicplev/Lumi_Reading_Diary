import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/comments/teacher_comments_sheet.dart';
import '../../../core/widgets/inline_stream_error.dart';
import '../../../data/providers/student_detail_providers.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'reading_log_snapshot.dart';
import '../../../core/utils/image_decode.dart';

/// "Recent Reading" section on the teacher student-detail screen. Watches the
/// shared recent-logs provider; retry invalidates only this section's stream.
/// Navigation ("View all") and the comment sheet stay with the parent via
/// callbacks.
class ReadingHistorySection extends ConsumerWidget {
  final StudentDetailLookup lookup;
  final VoidCallback onViewAll;
  final void Function(ReadingLogSnapshot snap) onOpenLogComments;

  const ReadingHistorySection({
    super.key,
    required this.lookup,
    required this.onViewAll,
    required this.onOpenLogComments,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(studentRecentLogsProvider(lookup));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Reading', style: LumiType.subhead),
            GestureDetector(
              onTap: onViewAll,
              child: Text(
                'View all',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        snapshot.when(
          error: (_, __) => InlineStreamError(
            message: "Couldn't load reading history.",
            onRetry: () => ref.invalidate(studentRecentLogsProvider(lookup)),
          ),
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          ),
          data: (querySnapshot) {
            final logs = toReadingLogSnapshots(querySnapshot);
            if (logs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: LumiTokens.paper,
                  borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                  border: Border.all(color: LumiTokens.rule),
                ),
                child: Center(
                  child: Text(
                    'No reading history yet',
                    style: LumiType.caption,
                  ),
                ),
              );
            }

            final groups = _groupRecentLogs(logs).take(5).toList();
            return Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
                border: Border.all(color: LumiTokens.rule),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < groups.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == groups.length - 1 ? 0 : 6,
                      ),
                      child: _ReadingGroupRow(
                        group: groups[i],
                        schoolId: lookup.schoolId,
                        onOpenLogComments: onOpenLogComments,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// Groups consecutive logs of the same book on the same day so repeated
  /// sessions collapse into one "N sessions · total min" row.
  List<List<ReadingLogSnapshot>> _groupRecentLogs(
      List<ReadingLogSnapshot> logs) {
    String key(ReadingLogSnapshot l) {
      final day = '${l.date.year}-${l.date.month}-${l.date.day}';
      final book =
          l.bookTitles.isNotEmpty ? l.bookTitles.join('|') : '__free__';
      return '$day::$book';
    }

    final groups = <List<ReadingLogSnapshot>>[];
    for (final log in logs) {
      List<ReadingLogSnapshot>? target;
      for (final grp in groups) {
        if (key(grp.first) == key(log)) {
          target = grp;
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
}

class _ReadingGroupRow extends StatelessWidget {
  final List<ReadingLogSnapshot> group;
  final String schoolId;
  final void Function(ReadingLogSnapshot snap) onOpenLogComments;

  const _ReadingGroupRow({
    required this.group,
    required this.schoolId,
    required this.onOpenLogComments,
  });

  @override
  Widget build(BuildContext context) {
    final rep = group.first; // most recent in the group
    final dateStr = formatCommentDate(rep.date);
    final books =
        rep.bookTitles.isNotEmpty ? rep.bookTitles.join(', ') : 'Free reading';
    final totalMinutes = group.fold<int>(0, (acc, l) => acc + l.minutesRead);
    final sessions = group.length;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Meta line: "16 Jun · 5 sessions · 85 min" (sessions omitted when 1).
    final meta = sessions > 1
        ? '$dateStr · $sessions sessions · $totalMinutes min'
        : '$dateStr · $totalMinutes min';

    final hasAudio = group.any((l) => l.comprehensionAudioPath != null);
    final audioPending = group.every((l) =>
        l.comprehensionAudioPath == null || !l.comprehensionAudioUploaded);
    final hasUnread = group.any((l) => l.hasUnreadForTeacher(uid));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onOpenLogComments(rep),
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: LumiTokens.cream,
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          ),
          child: Row(
            children: [
              // Left: title + meta stacked
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            books,
                            style: LumiType.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Subtle one-tap marker: books inferred from assignments,
                        // not parent-confirmed.
                        if (group.any((l) => l.isQuickLog)) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                'Quick log — books inferred from assignments, '
                                'not confirmed by the parent',
                            triggerMode: TooltipTriggerMode.tap,
                            child: Icon(
                              Icons.bolt,
                              size: 15,
                              color: LumiTokens.muted.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: LumiType.caption.copyWith(color: LumiTokens.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right: feeling blob + recording + comment indicators
              if (rep.childFeeling != null)
                Image.asset(
                  'assets/blobs/blob-${rep.childFeeling}.png',
                  width: 18,
                  cacheWidth: decodeCacheSize(context, 18),
                  height: 18,
                ),
              if (hasAudio) ...[
                const SizedBox(width: 8),
                RecordingAffordance(
                  schoolId: schoolId,
                  pending: audioPending,
                ),
              ],
              const SizedBox(width: 10),
              CommentAffordance(
                hasUnread: hasUnread,
                schoolId: schoolId,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
