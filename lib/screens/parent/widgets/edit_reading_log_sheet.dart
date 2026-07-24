import 'package:flutter/material.dart';

import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../services/offline_service.dart';
import '../../../services/reading_log_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Owner-scoped "Edit this log" sheet (plan §5.2). Editable fields mirror the
/// rules' contentUpdateIsValid set: minutes, books, notes. The DATE is
/// deliberately not editable — occurredOn is immutable; a wrong-day fix is
/// remove + re-log. Returns the updated log via the sheet's result, or null
/// when nothing was saved.
///
/// [isPending] switches the save path to the offline outbox (Edit pending,
/// §7.1): the queued payload is mutated in place under the SAME log ID, so
/// the eventual replay still writes exactly one session.
Future<ReadingLogModel?> showEditReadingLogSheet(
  BuildContext context,
  ReadingLogModel log, {
  bool isPending = false,
}) {
  return showModalBottomSheet<ReadingLogModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _EditReadingLogSheet(log: log, isPending: isPending),
  );
}

class _EditReadingLogSheet extends StatefulWidget {
  const _EditReadingLogSheet({required this.log, required this.isPending});

  final ReadingLogModel log;
  final bool isPending;

  @override
  State<_EditReadingLogSheet> createState() => _EditReadingLogSheetState();
}

class _EditReadingLogSheetState extends State<_EditReadingLogSheet> {
  late int _minutes;
  late List<String> _titles;
  late final TextEditingController _notesController;
  late final TextEditingController _addBookController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _minutes = widget.log.minutesRead;
    _titles = List<String>.from(widget.log.bookTitles);
    _notesController = TextEditingController(text: widget.log.notes ?? '');
    _addBookController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _addBookController.dispose();
    super.dispose();
  }

  void _bumpMinutes(int delta) {
    setState(() => _minutes = (_minutes + delta).clamp(1, 240));
  }

  void _commitTypedTitle() {
    final title = _addBookController.text.trim();
    if (title.isEmpty) return;
    final exists =
        _titles.any((t) => t.toLowerCase() == title.toLowerCase());
    setState(() {
      if (!exists) _titles.add(title);
      _addBookController.clear();
    });
  }

  bool get _canSave => !_saving && _minutes >= 1 && _titles.isNotEmpty;

  Future<void> _save() async {
    // Typed-but-uncommitted text still counts (§4.2 auto-commit rule).
    _commitTypedTitle();
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final ReadingLogModel? updated;
      if (widget.isPending) {
        updated = await OfflineService.instance.editPendingReadingLog(
          widget.log.id,
          minutesRead: _minutes,
          bookTitles: _titles,
          notes: _notesController.text,
        );
      } else {
        updated = await ReadingLogService.instance.updateOwnLog(
          widget.log,
          minutesRead: _minutes,
          bookTitles: _titles,
          notes: _notesController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(updated);
      showLumiToast(
        message: widget.isPending ? 'Pending log updated' : 'Log updated',
        type: LumiToastType.success,
      );
    } on ReadingLogEditOfflineException {
      if (!mounted) return;
      setState(() => _saving = false);
      showLumiToast(
        message: "You're offline — reconnect to edit this log.",
        type: LumiToastType.info,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showLumiToast(
        message: "Couldn't save changes. Please try again.",
        type: LumiToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
      ),
      padding: EdgeInsets.fromLTRB(
          LumiTokens.space5, LumiTokens.space4, LumiTokens.space5,
          LumiTokens.space5 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit this log', style: LumiType.subhead),
            const SizedBox(height: 4),
            Text(
              'The session date can\'t be changed — remove the session and '
              'log again if it\'s on the wrong day.',
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: LumiTokens.space4),
            Text('MINUTES',
                style: LumiType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: LumiTokens.muted)),
            const SizedBox(height: LumiTokens.space2),
            Row(
              children: [
                _Stepper(
                  icon: Icons.remove_rounded,
                  semanticLabel: 'Decrease minutes',
                  onTap: _saving ? null : () => _bumpMinutes(-5),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: LumiTokens.space4),
                  child: Text('$_minutes min',
                      style: LumiType.subhead
                          .copyWith(fontWeight: FontWeight.w800)),
                ),
                _Stepper(
                  icon: Icons.add_rounded,
                  semanticLabel: 'Increase minutes',
                  onTap: _saving ? null : () => _bumpMinutes(5),
                ),
              ],
            ),
            const SizedBox(height: LumiTokens.space4),
            Text('BOOKS',
                style: LumiType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: LumiTokens.muted)),
            const SizedBox(height: LumiTokens.space2),
            Wrap(
              spacing: LumiTokens.space2,
              runSpacing: LumiTokens.space2,
              children: [
                for (final title in _titles)
                  InputChip(
                    label: Text(title),
                    onDeleted: _saving || _titles.length == 1
                        ? null
                        : () => setState(() => _titles.remove(title)),
                    deleteButtonTooltipMessage: 'Remove $title',
                  ),
              ],
            ),
            const SizedBox(height: LumiTokens.space2),
            TextField(
              controller: _addBookController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _commitTypedTitle(),
              decoration: InputDecoration(
                hintText: 'Add a book title',
                filled: true,
                fillColor: LumiTokens.cream,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
              ),
            ),
            const SizedBox(height: LumiTokens.space4),
            Text('NOTES',
                style: LumiType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: LumiTokens.muted)),
            const SizedBox(height: LumiTokens.space2),
            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Anything to add? (optional)',
                filled: true,
                fillColor: LumiTokens.cream,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
              ),
            ),
            const SizedBox(height: LumiTokens.space5),
            LumiPrimaryButton(
              onPressed: _canSave ? _save : null,
              isLoading: _saving,
              isFullWidth: true,
              text: 'Save changes',
              icon: Icons.check_rounded,
              color: LumiTokens.red,
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: LumiTokens.cream,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: ConstrainedBox(
            // 44pt targets (§3.6) — fixes the 36pt steppers pattern.
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Icon(icon, size: 22, color: LumiTokens.ink),
          ),
        ),
      ),
    );
  }
}
