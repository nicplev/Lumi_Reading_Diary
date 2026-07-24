import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/school_time.dart';
import '../../../core/widgets/lumi/lumi_toast.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/models/student_model.dart';
import '../../../services/firebase_service.dart';
import '../../../services/reading_log_service.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../parent_logging_copy.dart';
import 'edit_reading_log_sheet.dart';

/// "Tonight's sessions" review sheet (plan §5.1) — the durable recovery
/// layer behind every Review action. Live-streams the day's sessions with
/// full provenance; Edit/Remove render ONLY on the caller's own records;
/// other-guardian and teacher records are view-only.
void showTodaySessionsSheet(
  BuildContext context, {
  required StudentModel student,
  required String myUid,
  required String timezone,
  required String schoolToday,
  VoidCallback? onAddAnotherSession,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TodaySessionsSheet(
      student: student,
      myUid: myUid,
      timezone: timezone,
      schoolToday: schoolToday,
      onAddAnotherSession: onAddAnotherSession,
    ),
  );
}

class _TodaySessionsSheet extends StatefulWidget {
  const _TodaySessionsSheet({
    required this.student,
    required this.myUid,
    required this.timezone,
    required this.schoolToday,
    this.onAddAnotherSession,
  });

  final StudentModel student;
  final String myUid;
  final String timezone;
  final String schoolToday;
  final VoidCallback? onAddAnotherSession;

  @override
  State<_TodaySessionsSheet> createState() => _TodaySessionsSheetState();
}

class _TodaySessionsSheetState extends State<_TodaySessionsSheet> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _logsStream;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // ±1-day window, bucketed client-side by occurredOn — same day maths as
    // the Home row and the server.
    final start = SchoolTime.utcRangeForLocalDay(
      SchoolTime.shiftDays(widget.schoolToday, -1),
      widget.timezone,
    ).startInclusive;
    final end = SchoolTime.utcRangeForLocalDay(
      SchoolTime.shiftDays(widget.schoolToday, 1),
      widget.timezone,
    ).endExclusive;
    _logsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.student.schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: widget.student.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThan: Timestamp.fromDate(end))
        .orderBy('date', descending: false)
        .snapshots();
  }

  List<ReadingLogModel> _todaySessions(
      QuerySnapshot<Map<String, dynamic>>? snap) {
    if (snap == null) return const [];
    return snap.docs
        .map(ReadingLogModel.fromFirestore)
        .where((log) =>
            (log.occurredOn ??
                SchoolTime.localDateString(log.date, widget.timezone)) ==
            widget.schoolToday)
        .toList();
  }

  Future<void> _edit(ReadingLogModel log) async {
    if (_busy) return;
    await showEditReadingLogSheet(context, log);
  }

  Future<void> _remove(
      ReadingLogModel log, List<ReadingLogModel> sessions) async {
    if (_busy) return;
    final qualifying = sessions.where((s) => s.isHomeContext).length;
    final isLast = qualifying <= 1 && log.isHomeContext;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove my session?'),
        content: Text(
          isLast
              ? ParentLoggingCopy.removeLastSessionWarning(
                  widget.student.firstName)
              : 'This removes just this session '
                  '(${log.minutesRead} min). Other sessions are untouched.',
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
      unawaited(AnalyticsService.instance.logSessionRemoved());
      if (!mounted) return;
      setState(() => _busy = false);
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
    final dayDisplay = DateFormat('EEEE d MMMM')
        .format(DateTime.parse('${widget.schoolToday}T12:00:00'));
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(LumiTokens.radiusXL)),
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _logsStream,
          builder: (context, snapshot) {
            final sessions = _todaySessions(snapshot.data);
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(LumiTokens.space5),
              children: [
                Text('Tonight — $dayDisplay (school time)',
                    style: LumiType.subhead),
                const SizedBox(height: LumiTokens.space2),
                Text(
                  '${widget.student.firstName} · '
                  '${sessions.fold<int>(0, (t, s) => t + s.minutesRead)} min '
                  'across ${sessions.length} '
                  'session${sessions.length == 1 ? '' : 's'}',
                  style: LumiType.caption.copyWith(color: LumiTokens.muted),
                ),
                const SizedBox(height: LumiTokens.space4),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    sessions.isEmpty)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(LumiTokens.space5),
                    child: CircularProgressIndicator(color: LumiTokens.red),
                  ))
                else if (sessions.isEmpty)
                  Text('No reading recorded yet tonight.',
                      style: LumiType.body)
                else
                  for (final session in sessions) ...[
                    _SessionCard(
                      session: session,
                      isMine: session.parentId == widget.myUid,
                      busy: _busy,
                      onEdit: () => _edit(session),
                      onRemove: () => _remove(session, sessions),
                    ),
                    const SizedBox(height: LumiTokens.space3),
                  ],
                if (widget.onAddAnotherSession != null) ...[
                  const SizedBox(height: LumiTokens.space2),
                  Center(
                    child: TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              widget.onAddAnotherSession!();
                            },
                      icon: const Icon(Icons.add_circle_outline,
                          color: LumiTokens.red),
                      label: Text('Add another session',
                          style: LumiType.body.copyWith(
                              color: LumiTokens.red,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.isMine,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
  });

  final ReadingLogModel session;
  final bool isMine;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final titleLine = session.titleUnresolved || session.bookTitles.isEmpty
        ? 'Title to add'
        : session.bookTitles.join(', ');
    final provenance = [
      session.isClassroomContext
          ? 'Class reading'
          : (isMine ? 'Logged by you' : 'Logged by ${session.loggedByDisplay}'),
      DateFormat('h:mm a').format(session.date),
      if (session.editedAt != null)
        'Edited ${DateFormat('h:mm a').format(session.editedAt!)}',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(LumiTokens.space4),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${session.minutesRead} min · $titleLine',
                style: LumiType.body.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(provenance,
                style: LumiType.caption.copyWith(color: LumiTokens.muted)),
            if (isMine && !session.isClassroomContext) ...[
              const SizedBox(height: LumiTokens.space2),
              Row(
                children: [
                  _ActionButton(
                    label: ParentLoggingCopy.editThisLog,
                    onPressed: busy ? null : onEdit,
                  ),
                  const SizedBox(width: LumiTokens.space3),
                  _ActionButton(
                    label: 'Remove my session',
                    destructive: true,
                    onPressed: busy ? null : onRemove,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? LumiTokens.red : LumiTokens.ink;
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
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                style: LumiType.caption.copyWith(
                  color: color,
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
