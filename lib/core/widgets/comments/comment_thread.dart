import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/log_comment_model.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/providers/user_provider.dart';
import '../../../services/reading_log_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_spacing.dart';

/// A threaded comment conversation attached to a reading log, shared by the
/// parent and teacher reading-history surfaces.
///
/// Renders the live thread plus a composer, and clears the unread badge for the
/// current user on view. The caller supplies the [authorRole] (which side is
/// posting) and an [accentColor] for the viewer's own bubbles; the author's
/// identity is resolved from the signed-in user.
class CommentThread extends ConsumerStatefulWidget {
  const CommentThread({
    super.key,
    required this.log,
    required this.authorRole,
    required this.accentColor,
  });

  final ReadingLogModel log;
  final CommentAuthorRole authorRole;
  final Color accentColor;

  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
  final _controller = TextEditingController();
  final _service = ReadingLogService.instance;
  bool _sending = false;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    // Clear the unread badge once the thread is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_uid.isNotEmpty) {
        _service.markCommentsRead(widget.log, uid: _uid);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final authorId = _uid;
    if (authorId.isEmpty) return;

    final user = ref.read(userProvider).value;
    final fallbackName =
        widget.authorRole == CommentAuthorRole.teacher ? 'Teacher' : 'Parent';
    final authorName = (user?.fullName.trim().isNotEmpty ?? false)
        ? user!.fullName
        : fallbackName;

    setState(() => _sending = true);
    try {
      await _service.addComment(
        widget.log,
        body: text,
        authorRole: widget.authorRole,
        authorId: authorId,
        authorName: authorName,
      );
      _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<List<LogCommentModel>>(
          stream: _service.commentsStream(widget.log),
          builder: (context, snapshot) {
            final comments = snapshot.data ?? const <LogCommentModel>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            if (comments.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No comments yet. Start the conversation.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              );
            }
            return Column(
              children: [
                for (final comment in comments)
                  _CommentBubble(
                    comment: comment,
                    isMine: comment.authorId == _uid,
                    accentColor: widget.accentColor,
                  ),
              ],
            );
          },
        ),
        LumiGap.xs,
        _Composer(
          controller: _controller,
          sending: _sending,
          accentColor: widget.accentColor,
          onSend: _send,
        ),
      ],
    );
  }
}

/// A single message bubble: the viewer's own messages tint with the accent and
/// align right; the other party's are neutral grey and align left.
class _CommentBubble extends StatelessWidget {
  const _CommentBubble({
    required this.comment,
    required this.isMine,
    required this.accentColor,
  });

  final LogCommentModel comment;
  final bool isMine;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final bubbleColor =
        isMine ? accentColor.withValues(alpha: 0.16) : AppColors.divider;
    final meta =
        '${comment.authorName} · ${DateFormat.jm().format(comment.createdAt)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: Text(
              comment.body,
              style: const TextStyle(
                color: AppColors.charcoal,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
            child: Text(
              meta,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The reply input row: a rounded text field plus a send affordance that shows
/// a spinner while a write is in flight.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.accentColor,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Color accentColor;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borderOf(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: color),
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14, color: AppColors.charcoal),
            decoration: InputDecoration(
              hintText: 'Write a comment…',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              enabledBorder: borderOf(AppColors.divider),
              border: borderOf(AppColors.divider),
              focusedBorder: borderOf(accentColor),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        LumiGap.horizontalXS,
        if (sending)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          IconButton(
            onPressed: () => onSend(),
            icon: Icon(Icons.send_rounded, color: accentColor),
            tooltip: 'Send',
          ),
      ],
    );
  }
}
