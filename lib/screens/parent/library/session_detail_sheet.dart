import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/school_time.dart';
import '../../../core/widgets/comments/comment_thread.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/log_comment_model.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/providers/access_provider.dart';
import '../../../data/providers/school_settings_provider.dart';
import '../../../services/firebase_service.dart';
import '../../../services/reading_log_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../parent_logging_copy.dart';
import '../widgets/edit_reading_log_sheet.dart';
import 'reading_feeling_visuals.dart';
import '../../../core/utils/image_decode.dart';

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

class _SessionDetailSheet extends ConsumerStatefulWidget {
  final ReadingLogModel log;

  const _SessionDetailSheet({required this.log});

  @override
  ConsumerState<_SessionDetailSheet> createState() =>
      _SessionDetailSheetState();
}

class _SessionDetailSheetState extends ConsumerState<_SessionDetailSheet> {
  late ReadingLogModel log;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    log = widget.log;
  }

  /// Owner-scoped recovery (§5): only the session's creator sees Edit/Remove
  /// — other-guardian and teacher records stay view-only.
  bool get _isMine =>
      FirebaseService.instance.currentUser?.uid == log.parentId &&
      log.loggedByRole != LoggedByRole.teacher;

  Future<void> _edit() async {
    if (_busy) return;
    final updated = await showEditReadingLogSheet(context, log);
    if (updated != null && mounted) setState(() => log = updated);
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() => _busy = true);
    final school = ref.read(schoolByIdProvider(log.schoolId)).value;
    final timezone = school?.timezone ?? SchoolTime.defaultTimezone;
    final occurredOn =
        log.occurredOn ?? SchoolTime.localDateString(log.date, timezone);
    int qualifying = 2; // benign default: skip the strong warning on failure
    try {
      qualifying = await ReadingLogService.instance.countHomeSessionsOn(
        schoolId: log.schoolId,
        studentId: log.studentId,
        occurredOn: occurredOn,
        timezone: timezone,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);

    final isLast = qualifying <= 1 && log.isHomeContext;
    const firstName = 'your child';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove my session?'),
        content: Text(
          isLast
              ? ParentLoggingCopy.removeLastSessionWarning(firstName)
              : 'This removes just this session (${log.minutesRead} min) '
                  'and its comments. Other sessions are untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: LumiTokens.red),
            child: const Text('Remove my session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ReadingLogService.instance.deleteOwnLog(log);
      if (!mounted) return;
      Navigator.of(context).pop();
      showLumiToast(
          message: ParentLoggingCopy.undoDone, type: LumiToastType.info);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showLumiToast(
        message: "Couldn't remove the session. Please try again.",
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hide the parent↔teacher comment thread when the school has messaging off.
    final messagingOn = ref.watch(messagingEnabledProvider(log.schoolId));
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
                            if (log.editedAt != null)
                              'Edited '
                                  '${DateFormat('d MMM, h:mm a').format(log.editedAt!)}',
                          ].join('  ·  '),
                          style: LumiType.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Owner-scoped durable recovery (§5): visible ONLY on the
            // caller's own sessions. Back/dismiss only navigate — removal is
            // always this explicit action plus a confirm.
            if (_isMine)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    LumiTokens.space5, LumiTokens.space2, LumiTokens.space5, 0),
                child: Row(
                  children: [
                    _OwnerAction(
                      label: ParentLoggingCopy.editThisLog,
                      onPressed: _busy ? null : _edit,
                    ),
                    const SizedBox(width: LumiTokens.space4),
                    _OwnerAction(
                      label: 'Remove my session',
                      destructive: true,
                      onPressed: _busy ? null : _remove,
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
                          cacheWidth: decodeCacheSize(context, 36),
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
                  if (messagingOn) ...[
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerAction extends StatelessWidget {
  const _OwnerAction({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Align(
            widthFactor: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: LumiType.caption.copyWith(
                  color: destructive ? LumiTokens.red : LumiTokens.ink,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
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
