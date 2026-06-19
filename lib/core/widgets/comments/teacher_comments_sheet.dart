import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../data/models/log_comment_model.dart';
import '../../../data/models/reading_log_model.dart';
import '../audio/comprehension_audio_player.dart';
import 'comment_thread.dart';

/// A compact comment icon with an unread dot, shown on a reading-log row so a
/// teacher can see at a glance which logs have an unanswered parent message.
class CommentAffordance extends StatelessWidget {
  final bool hasUnread;

  const CommentAffordance({super.key, required this.hasUnread});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.mode_comment_outlined,
          size: 18,
          color: hasUnread ? LumiTokens.green : LumiTokens.muted,
        ),
        if (hasUnread)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: LumiTokens.green,
                shape: BoxShape.circle,
                border: Border.all(color: LumiTokens.paper, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

/// A mic icon shown on a reading-log row that has a comprehension recording, so
/// a teacher can spot at a glance which logs have audio. When the recording is
/// still uploading it renders muted ([pending]) — surfacing recordings that
/// exist but haven't landed in Storage yet.
class RecordingAffordance extends StatelessWidget {
  final bool pending;

  const RecordingAffordance({super.key, this.pending = false});

  @override
  Widget build(BuildContext context) {
    return Icon(
      pending ? Icons.mic_none_rounded : Icons.mic_rounded,
      size: 18,
      color: pending
          ? LumiTokens.muted.withValues(alpha: 0.5)
          : LumiTokens.muted,
    );
  }
}

/// Inline note shown in place of the player when a recording exists on the log
/// but its upload to Storage hasn't completed yet.
class _RecordingPendingNote extends StatelessWidget {
  const _RecordingPendingNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_none_rounded,
              size: 18, color: LumiTokens.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Recording is still uploading — it'll appear here once it lands.",
              style: LumiType.caption
                  .copyWith(color: LumiTokens.muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the teacher comment thread for a single reading [log] as a draggable
/// bottom sheet. Shared by the student-detail and reading-history surfaces so
/// the experience is identical wherever a teacher taps into a conversation.
void openTeacherCommentsSheet(
  BuildContext context, {
  required ReadingLogModel log,
  required String studentName,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => TeacherCommentsSheet(log: log, studentName: studentName),
  );
}

/// Bottom sheet hosting a reading log's comment thread for a teacher, with a
/// composer that lifts above the keyboard.
class TeacherCommentsSheet extends StatelessWidget {
  final ReadingLogModel log;
  final String studentName;

  const TeacherCommentsSheet({
    super.key,
    required this.log,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    final books =
        log.bookTitles.isNotEmpty ? log.bookTitles.join(', ') : 'Free reading';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.mode_comment_outlined,
                        size: 20, color: LumiTokens.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Comments', style: LumiType.subhead),
                          Text(
                            '$studentName · $books',
                            style: LumiType.caption
                                .copyWith(color: LumiTokens.muted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: LumiTokens.rule),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // The child's comprehension recording, when present. A log
                    // whose audio hasn't finished uploading shows a pending note
                    // rather than a broken player.
                    if (log.comprehensionAudioPath != null) ...[
                      if (log.hasComprehensionAudio)
                        ComprehensionAudioPlayer(
                          storagePath: log.comprehensionAudioPath!,
                          durationSec: log.comprehensionAudioDurationSec,
                          schoolId: log.schoolId,
                          logId: log.id,
                        )
                      else
                        const _RecordingPendingNote(),
                      const SizedBox(height: 16),
                    ],
                    CommentThread(
                      log: log,
                      authorRole: CommentAuthorRole.teacher,
                      accentColor: LumiTokens.green,
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
