import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/comments/comment_thread.dart';
import '../../../data/models/log_comment_model.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'reading_feeling_visuals.dart';

/// Library section accent. Bottom sheets render in an overlay above the screen
/// and so don't inherit the screen's `LumiSectionScope`; we use the library
/// yellow explicitly.
const _accent = LumiTokens.yellow;

/// Opens the reading-session detail sheet for a [log] — books, how it felt,
/// parent feedback/notes and the parent↔teacher comment thread.
void showSessionDetailSheet(BuildContext context, ReadingLogModel log) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SessionDetailSheet(log: log),
  );
}

class _SessionDetailSheet extends StatelessWidget {
  final ReadingLogModel log;

  const _SessionDetailSheet({required this.log});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.55],
      shouldCloseOnMinExtent: true,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LumiTokens.radiusXL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            // Header — date badge + session summary.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LumiTokens.space5,
                LumiTokens.space4,
                LumiTokens.space5,
                0,
              ),
              child: Row(
                children: [
                  _DateBadge(date: log.date),
                  const SizedBox(width: LumiTokens.space4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reading session', style: LumiType.subhead),
                        const SizedBox(height: LumiTokens.space1),
                        Text(
                          [
                            '${log.minutesRead} min',
                            if (log.loggedByName != null)
                              'Logged by ${log.loggedByDisplay}',
                          ].join('  ·  '),
                          style: LumiType.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LumiTokens.space4),
            const Divider(height: 1, color: LumiTokens.rule),
            // Scrollable detail.
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(LumiTokens.space5),
                children: [
                  _Label(
                    log.bookTitles.length == 1
                        ? 'Book'
                        : 'Books (${log.bookTitles.length})',
                  ),
                  const SizedBox(height: LumiTokens.space2),
                  ...log.bookTitles.map((title) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: LumiTokens.space2),
                        child: _BookRow(title: title),
                      )),
                  if (log.childFeeling != null) ...[
                    const SizedBox(height: LumiTokens.space4),
                    const _Label('How it felt'),
                    const SizedBox(height: LumiTokens.space2),
                    Row(
                      children: [
                        Image.asset(
                          feelingAsset(log.childFeeling!),
                          width: 36,
                          height: 36,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: LumiTokens.space3),
                        Text(
                          feelingLabel(log.childFeeling!),
                          style: LumiType.body,
                        ),
                      ],
                    ),
                  ],
                  if (log.parentCommentSelections.isNotEmpty) ...[
                    const SizedBox(height: LumiTokens.space4),
                    const _Label('Parent feedback'),
                    const SizedBox(height: LumiTokens.space2),
                    Wrap(
                      spacing: LumiTokens.space2,
                      runSpacing: LumiTokens.space2,
                      children: log.parentCommentSelections
                          .map((chip) => _Pill(text: chip))
                          .toList(),
                    ),
                  ],
                  if (log.notes != null && log.notes!.isNotEmpty) ...[
                    const SizedBox(height: LumiTokens.space4),
                    const _Label('Notes'),
                    const SizedBox(height: LumiTokens.space2),
                    Text(log.notes!, style: LumiType.body),
                  ],
                  const SizedBox(height: LumiTokens.space4),
                  const _Label('Comments'),
                  const SizedBox(height: LumiTokens.space2),
                  CommentThread(
                    log: log,
                    authorRole: CommentAuthorRole.parent,
                    accentColor: _accent,
                  ),
                  // Clear the keyboard inset so the composer stays visible.
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: LumiTokens.space2),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: LumiTokens.rule,
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        ),
      ),
    );
  }
}

class _DateBadge extends StatelessWidget {
  final DateTime date;

  const _DateBadge({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 56,
      decoration: BoxDecoration(
        color: LumiTokens.tintYellow,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('dd').format(date),
            style: LumiType.subhead.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: LumiType.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: LumiTokens.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final String title;

  const _BookRow({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space4,
        vertical: LumiTokens.space3,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: Row(
        children: [
          const Icon(Icons.menu_book_rounded, size: 20, color: _accent),
          const SizedBox(width: LumiTokens.space3),
          Expanded(
            child: Text(
              title,
              style: LumiType.body.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: LumiType.caption.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: LumiTokens.muted,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;

  const _Pill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space3,
        vertical: LumiTokens.space1,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.tintYellow,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: Text(
        text,
        style: LumiType.caption.copyWith(color: LumiTokens.ink),
      ),
    );
  }
}
