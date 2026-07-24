import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/analytics_service.dart';

import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/models/student_model.dart';
import '../../../services/firebase_service.dart';
import '../../../services/guardian_quick_log_prefs_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// One deduped picker entry with its provenance badges (§4.2): the same
/// title appearing as pinned AND assigned renders once with both badges.
class BookPickerEntry {
  BookPickerEntry(this.title);

  final String title;
  bool pinned = false;
  bool assigned = false;
  bool recent = false;
}

/// The result of a picker choice.
class BookPickerResult {
  const BookPickerResult({required this.title, required this.pin});

  final String title;

  /// True when the guardian asked to make this the child's pinned current
  /// book (persisted per guardian×child).
  final bool pin;
}

/// "Choose a book" sheet (§4.2): pinned/current first, then recents, then
/// assigned, then manual entry. One list, case-insensitively deduped, with
/// source badges. Choosing NEVER writes a session — the caller decides what
/// to do with the title. Pinning persists via GuardianQuickLogPrefsService.
Future<BookPickerResult?> showBookPickerSheet(
  BuildContext context, {
  required StudentModel student,
  required String myUid,
  required List<String> assignedTitles,
  String? pinnedTitle,
}) {
  return showModalBottomSheet<BookPickerResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _BookPickerSheet(
      student: student,
      myUid: myUid,
      assignedTitles: assignedTitles,
      pinnedTitle: pinnedTitle,
    ),
  );
}

class _BookPickerSheet extends StatefulWidget {
  const _BookPickerSheet({
    required this.student,
    required this.myUid,
    required this.assignedTitles,
    required this.pinnedTitle,
  });

  final StudentModel student;
  final String myUid;
  final List<String> assignedTitles;
  final String? pinnedTitle;

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  static const int _recentLimit = 3;

  final _manualController = TextEditingController();
  List<BookPickerEntry> _entries = const [];
  bool _loadingRecents = true;
  bool _pinChoice = true;

  @override
  void initState() {
    super.initState();
    _entries = _composeEntries(const []);
    _loadRecents();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  /// Last few distinct titles from this child's sessions (any guardian).
  /// Removing/failing recents never alters historical sessions — this is a
  /// read-only suggestion source.
  Future<void> _loadRecents() async {
    List<String> recents = const [];
    try {
      final snap = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.student.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.student.id)
          .orderBy('date', descending: true)
          .limit(15)
          .get();
      final seen = <String>{};
      recents = [
        for (final doc in snap.docs)
          for (final title in ReadingLogModel.fromFirestore(doc).bookTitles)
            if (title.trim().isNotEmpty &&
                seen.add(title.trim().toLowerCase()))
              title.trim(),
      ].take(_recentLimit).toList();
    } catch (_) {
      // Suggestions only — the picker still works without them.
    }
    if (!mounted) return;
    setState(() {
      _entries = _composeEntries(recents);
      _loadingRecents = false;
    });
  }

  /// One deduped, badge-carrying list in §4.2 order:
  /// pinned → recents → assigned.
  List<BookPickerEntry> _composeEntries(List<String> recents) {
    final byKey = <String, BookPickerEntry>{};
    BookPickerEntry entry(String title) =>
        byKey.putIfAbsent(title.toLowerCase(), () => BookPickerEntry(title));

    final pinned = widget.pinnedTitle;
    if (pinned != null && pinned.trim().isNotEmpty) {
      entry(pinned.trim()).pinned = true;
    }
    for (final title in recents) {
      entry(title).recent = true;
    }
    for (final title in widget.assignedTitles) {
      if (title.trim().isNotEmpty) entry(title.trim()).assigned = true;
    }
    final list = byKey.values.toList();
    int rank(BookPickerEntry e) => e.pinned
        ? 0
        : e.recent
            ? 1
            : 2;
    list.sort((a, b) => rank(a).compareTo(rank(b)));
    return list;
  }

  Future<void> _choose(String title, {required bool pin}) async {
    if (pin) {
      try {
        await GuardianQuickLogPrefsService.instance.setPinnedBook(
          schoolId: widget.student.schoolId,
          parentId: widget.myUid,
          studentId: widget.student.id,
          title: title,
        );
      } catch (_) {
        // The choice still returns; pinning is a convenience, not a gate.
      }
    }
    unawaited(AnalyticsService.instance.logBookChooserUsed());
    if (!mounted) return;
    Navigator.of(context).pop(BookPickerResult(title: title, pin: pin));
  }

  void _commitManual() {
    final title = _manualController.text.trim();
    if (title.isEmpty) return;
    _choose(title, pin: _pinChoice);
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
      padding: EdgeInsets.fromLTRB(LumiTokens.space5, LumiTokens.space4,
          LumiTokens.space5, LumiTokens.space5 + insets),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Choose a book for ${widget.student.firstName}',
                style: LumiType.subhead),
            const SizedBox(height: 4),
            Text(
              'Nothing is logged yet — this just sets the book the quick '
              'log will record.',
              style: LumiType.caption.copyWith(color: LumiTokens.muted),
            ),
            const SizedBox(height: LumiTokens.space4),
            if (_entries.isEmpty && _loadingRecents)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(LumiTokens.space4),
                child: CircularProgressIndicator(color: LumiTokens.red),
              ))
            else ...[
              for (final entry in _entries)
                _EntryTile(
                  entry: entry,
                  onTap: () => _choose(entry.title, pin: _pinChoice),
                ),
            ],
            const SizedBox(height: LumiTokens.space3),
            Text('SEARCH OR ADD A TITLE',
                style: LumiType.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: LumiTokens.muted)),
            const SizedBox(height: LumiTokens.space2),
            TextField(
              controller: _manualController,
              textInputAction: TextInputAction.done,
              // §4.2 auto-commit: keyboard Done commits the typed title —
              // no + icon anywhere in this sheet.
              onSubmitted: (_) => _commitManual(),
              decoration: InputDecoration(
                hintText: 'Type a title…',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: LumiTokens.cream,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
              ),
            ),
            const SizedBox(height: LumiTokens.space3),
            // Pinning is what makes the choice durable for one-tap logging;
            // defaulted on because Choose book exists to establish a
            // current book (§4.1). The checkbox keeps it explicit.
            CheckboxListTile(
              value: _pinChoice,
              onChanged: (v) => setState(() => _pinChoice = v ?? true),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: LumiTokens.red,
              title: Text(
                "Make this ${widget.student.firstName}'s current book",
                style: LumiType.body,
              ),
            ),
            const SizedBox(height: LumiTokens.space2),
            LumiPrimaryButton(
              onPressed: _commitManual,
              isFullWidth: true,
              text: 'Use this title',
              icon: Icons.check_rounded,
              color: LumiTokens.red,
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final BookPickerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badges = [
      if (entry.pinned) 'Pinned',
      if (entry.assigned) 'Assigned',
      if (entry.recent) 'Logged',
    ];
    return Semantics(
      button: true,
      label: '${entry.title}. ${badges.join(', ')}.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.menu_book_rounded,
                  size: 20, color: LumiTokens.red),
              const SizedBox(width: LumiTokens.space3),
              Expanded(
                child: Text(entry.title,
                    style:
                        LumiType.body.copyWith(fontWeight: FontWeight.w600)),
              ),
              for (final badge in badges) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: LumiTokens.cream,
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusPill),
                  ),
                  child: Text(badge,
                      style: LumiType.caption.copyWith(
                          fontSize: 11, color: LumiTokens.muted)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
