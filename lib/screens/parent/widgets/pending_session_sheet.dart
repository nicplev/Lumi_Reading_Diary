import 'package:flutter/material.dart';

import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/models/student_model.dart';
import '../../../services/offline_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../parent_logging_copy.dart';
import 'edit_reading_log_sheet.dart';

/// Review surface for a session that is saved on this phone but not yet
/// shared (§7.1). Two honest actions: Edit pending (mutates the queued
/// payload under the same log ID) and Cancel pending (nothing ever reaches
/// the server). Sync timing is the outbox's job — no fake "send now".
void showPendingSessionSheet(
  BuildContext context, {
  required StudentModel student,
  required ReadingLogModel pending,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _PendingSessionSheet(student: student, pending: pending),
  );
}

class _PendingSessionSheet extends StatelessWidget {
  const _PendingSessionSheet({required this.student, required this.pending});

  final StudentModel student;
  final ReadingLogModel pending;

  @override
  Widget build(BuildContext context) {
    final titleLine = pending.bookTitles.isEmpty
        ? 'Title to add'
        : pending.bookTitles.join(', ');
    return Container(
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
      ),
      padding: const EdgeInsets.all(LumiTokens.space5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${student.firstName} — session on this phone',
              style: LumiType.subhead),
          const SizedBox(height: LumiTokens.space2),
          Text(
            '${pending.minutesRead} min · $titleLine',
            style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            "${ParentLoggingCopy.pendingStatus}. It will sync when you're "
            'back online.',
            style: LumiType.caption.copyWith(color: LumiTokens.muted),
          ),
          const SizedBox(height: LumiTokens.space4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 12,
            leading: const Icon(Icons.edit_outlined, color: LumiTokens.ink),
            title: Text(ParentLoggingCopy.pendingEdit, style: LumiType.body),
            onTap: () async {
              final navigator = Navigator.of(context);
              await showEditReadingLogSheet(context, pending,
                  isPending: true);
              if (navigator.mounted) navigator.pop();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            minVerticalPadding: 12,
            leading:
                const Icon(Icons.delete_outline_rounded, color: LumiTokens.red),
            title: Text(ParentLoggingCopy.pendingCancel,
                style: LumiType.body.copyWith(color: LumiTokens.red)),
            onTap: () async {
              final navigator = Navigator.of(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel this pending session?'),
                  content: const Text(
                      'It was never shared with the school, so cancelling '
                      'removes it completely.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Keep it'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(
                          foregroundColor: LumiTokens.red),
                      child: const Text('Cancel pending'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              await OfflineService.instance
                  .cancelPendingReadingLog(pending.id);
              if (navigator.mounted) navigator.pop();
              showLumiToast(
                  message: ParentLoggingCopy.undoDone,
                  type: LumiToastType.info);
            },
          ),
        ],
      ),
    );
  }
}

/// The reconnect conflict prompt (§7.2): another guardian's session claimed
/// the day's slot while this device's quick log waited offline. The two
/// choices are explicit; nothing is ever merged or discarded silently.
Future<void> showQuickSlotConflictDialog(
  BuildContext context, {
  required StudentModel student,
  required String pendingLogId,
  String? winnerName,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${winnerName ?? 'Someone else'} logged reading while you '
          'were offline'),
      content: Text(
          'Was your saved session for ${student.firstName} the same reading, '
          'or a different one?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Same session — discard mine'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Different session — add mine'),
        ),
      ],
    ),
  );
  if (choice == null) return; // dismissed — decide later, nothing changes
  await OfflineService.instance.resolveQuickSlotConflict(
    logId: pendingLogId,
    keepMine: choice,
  );
  showLumiToast(
    message: choice
        ? 'Added as a separate session — syncing now.'
        : 'Discarded. Nothing was shared.',
    type: LumiToastType.info,
  );
}
