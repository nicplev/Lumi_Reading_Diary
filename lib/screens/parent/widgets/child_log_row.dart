import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/models/reading_log_model.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../../core/widgets/lumi/student_avatar.dart';
import '../../../data/models/student_model.dart';
import '../parent_logging_copy.dart';

/// The child-keyed state of one Home logging row
/// (docs/PARENT_LOGGING_FLOW_PLAN.md §3.2). Derived by [deriveChildLogRowState]
/// — a pure function so every transition is unit-testable without widgets.
sealed class ChildLogRowState {
  const ChildLogRowState();
}

/// One tap creates the default home quick session.
class RowReady extends ChildLogRowState {
  const RowReady({
    required this.bookTitles,
    required this.usualMinutes,
    this.goalMinutes,
  });

  /// Union of the child's effective assigned titles (D3), or the pinned book.
  final List<String> bookTitles;
  final int usualMinutes;

  /// The allocation target, shown as "School goal" when it differs from the
  /// guardian's usual duration (Phase 2 prefs); null when identical/absent.
  final int? goalMinutes;
}

/// No resolvable book — the action becomes "Choose book"; no write happens.
class RowNeedsBook extends ChildLogRowState {
  const RowNeedsBook();
}

/// Locked from the moment of the tap until a receipt or failure.
class RowSubmitting extends ChildLogRowState {
  const RowSubmitting();
}

/// This guardian's quick log just landed — the immediate, confirmation-free
/// undo layer targets exactly [log].
class RowJustCreatedByMe extends ChildLogRowState {
  const RowJustCreatedByMe({required this.log});
  final ReadingLogModel log;
}

/// One home session exists and someone else recorded it. View-only.
class RowLoggedByOther extends ChildLogRowState {
  const RowLoggedByOther({required this.log});
  final ReadingLogModel log;
}

/// Two or more home sessions today.
class RowMultiSessions extends ChildLogRowState {
  const RowMultiSessions({required this.sessions, required this.totalMinutes});
  final int sessions;
  final int totalMinutes;
}

/// Classroom reading happened today but no home session yet — display it
/// without letting it satisfy the home slot (quick log stays available).
class RowClassroomOnly extends ChildLogRowState {
  const RowClassroomOnly({required this.inner, required this.classroomMinutes});

  /// What the row would be ignoring classroom logs (Ready or NeedsBook).
  final ChildLogRowState inner;
  final int classroomMinutes;
}

/// A session is saved on this phone but hasn't reached the school yet
/// (offline outbox). Explicit, per-row — never inferred from snapshot
/// metadata. Review offers Edit pending / Cancel pending.
class RowOfflinePending extends ChildLogRowState {
  const RowOfflinePending({required this.pending});
  final ReadingLogModel pending;
}

/// A queued quick log collided with another guardian's session while this
/// device was offline — only the guardian can resolve it (§7.2).
class RowConflict extends ChildLogRowState {
  const RowConflict({required this.pendingLogId});
  final String pendingLogId;
}

/// Child access is not live: neutral, no affordance, no local write.
class RowAccessUnavailable extends ChildLogRowState {
  const RowAccessUnavailable();
}

/// School turned quick logging off: the row body still opens the detailed
/// flow, but no dead trailing button is dangled.
class RowQuickLogDisabled extends ChildLogRowState {
  const RowQuickLogDisabled();
}

/// Derives the row state for one child. Pure — all inputs are values.
///
/// [todayLogs] must already be bucketed to the school-local day; this
/// function splits home vs classroom context itself. [justCreatedLogId] is
/// the session-local id returned by the most recent quick log from THIS
/// widget (the immediate-undo layer); durable recovery lives in the review
/// sheet regardless.
ChildLogRowState deriveChildLogRowState({
  required StudentModel student,
  required List<ReadingLogModel> todayLogs,
  required List<String> resolvedBookTitles,
  required int usualMinutes,
  required bool quickLoggingEnabled,
  required bool submitting,
  required String myUid,
  String? justCreatedLogId,
  int? goalMinutes,
  List<ReadingLogModel> pendingLogs = const [],
  String? conflictLogId,
}) {
  if (!student.hasActiveAccess) return const RowAccessUnavailable();
  if (submitting) return const RowSubmitting();
  // A parked slot conflict outranks everything else the guardian could do:
  // it's their decision, and no further quick logging makes sense until made.
  if (conflictLogId != null) return RowConflict(pendingLogId: conflictLogId);
  // Saved-on-this-phone sessions outrank Ready: the row must say the log
  // exists but hasn't been shared, not invite a duplicate.
  if (pendingLogs.isNotEmpty && todayLogs.where((l) => l.isHomeContext).isEmpty) {
    return RowOfflinePending(pending: pendingLogs.first);
  }

  final homeLogs = todayLogs.where((l) => l.isHomeContext).toList();
  final classroomLogs = todayLogs.where((l) => l.isClassroomContext).toList();

  if (homeLogs.isNotEmpty) {
    if (homeLogs.length == 1) {
      final log = homeLogs.single;
      if (log.id == justCreatedLogId && log.parentId == myUid) {
        return RowJustCreatedByMe(log: log);
      }
      if (log.parentId != myUid) return RowLoggedByOther(log: log);
      // My own earlier session (app restart, other device): the immediate
      // undo window has passed — durable review is the recovery path.
      return RowMultiSessions(sessions: 1, totalMinutes: log.minutesRead);
    }
    return RowMultiSessions(
      sessions: homeLogs.length,
      totalMinutes:
          homeLogs.fold<int>(0, (total, log) => total + log.minutesRead),
    );
  }

  final ChildLogRowState base;
  if (!quickLoggingEnabled) {
    base = const RowQuickLogDisabled();
  } else if (resolvedBookTitles.isEmpty) {
    base = const RowNeedsBook();
  } else {
    base = RowReady(
      bookTitles: resolvedBookTitles,
      usualMinutes: usualMinutes,
      goalMinutes: goalMinutes,
    );
  }

  if (classroomLogs.isNotEmpty) {
    return RowClassroomOnly(
      inner: base,
      classroomMinutes: classroomLogs.fold<int>(
          0, (total, log) => total + log.minutesRead),
    );
  }
  return base;
}

/// One child's logging row: stable two-line layout with a fixed-width
/// trailing slot whose CONTENT swaps per state — nothing is inserted or
/// removed, so logging one child never moves another child's row and the
/// trailing button never morphs into Undo under the same finger (§3.1–3.3).
class ChildLogRow extends StatelessWidget {
  const ChildLogRow({
    super.key,
    required this.student,
    required this.state,
    required this.onOpenDetail,
    this.onQuickLog,
    this.onChooseBook,
    this.onUndo,
    this.onReview,
    this.dateMismatchNote,
  });

  final StudentModel student;
  final ChildLogRowState state;

  /// Row body tap — always the detailed flow (except access-unavailable).
  final VoidCallback onOpenDetail;
  final VoidCallback? onQuickLog;
  final VoidCallback? onChooseBook;
  final VoidCallback? onUndo;
  final VoidCallback? onReview;

  /// "Saving as Thu 24 Jul (school time)" — set when device day ≠ school day.
  final String? dateMismatchNote;

  /// Trailing slot width. Fixed so state swaps can't shift the layout.
  static const double trailingWidth = 128;

  /// The status strip's reserved height — CONSTANT across every state so
  /// swapping in the inline Undo (or any other action content) can never
  /// change the row's height (§3.1), and inline actions get a true 44pt
  /// target (§3.6).
  static const double statusStripHeight = 44;

  /// While submitting the whole row is inert — the body must not be able to
  /// open a second flow mid-write (§3.2).
  bool get _bodyEnabled =>
      state is! RowAccessUnavailable && state is! RowSubmitting;

  @override
  Widget build(BuildContext context) {
    // At accessibility text sizes the trailing action wraps to its own
    // full-width line BELOW the status line — decided by text scale alone
    // (never by logging state), so rows still never reflow on a state
    // change and nothing is elided (§3.6).
    final wrapAction =
        MediaQuery.textScalerOf(context).scale(14) >= 14 * 1.6;

    final info = _RowInfo(
      student: student,
      state: state,
      dateMismatchNote: dateMismatchNote,
      onUndo: onUndo,
    );
    final action = _TrailingAction(
      student: student,
      state: state,
      onQuickLog: onQuickLog,
      onChooseBook: onChooseBook,
      onReview: onReview,
      fixedWidth: wrapAction ? null : trailingWidth,
    );

    return InkWell(
      onTap: _bodyEnabled ? onOpenDetail : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: wrapAction
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    _avatar(),
                    const SizedBox(width: 12),
                    Expanded(child: info),
                  ]),
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              )
            : Row(children: [
                _avatar(),
                const SizedBox(width: 12),
                Expanded(child: info),
                const SizedBox(width: 8),
                action,
              ]),
      ),
    );
  }

  Widget _avatar() => ExcludeSemantics(
        child: StudentAvatar.fromStudent(student, size: 44),
      );
}

class _RowInfo extends StatelessWidget {
  const _RowInfo({
    required this.student,
    required this.state,
    required this.dateMismatchNote,
    required this.onUndo,
  });

  final StudentModel student;
  final ChildLogRowState state;
  final String? dateMismatchNote;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final muted = LumiType.caption.copyWith(color: LumiTokens.muted);

    String status;
    Widget? statusExtra;
    switch (s) {
      case RowReady():
        // When the guardian's usual differs from the allocation target, the
        // usual lives on the button and the school's goal is disclosed here
        // — teacher target and parent-reported time never conflate (§6.4).
        status = s.goalMinutes != null
            ? ParentLoggingCopy.schoolGoal(s.goalMinutes!, s.bookTitles.first)
            : s.bookTitles.length > 1
                ? ParentLoggingCopy.readyStatusMulti(s.bookTitles.first,
                    s.bookTitles.length - 1, s.usualMinutes)
                : ParentLoggingCopy.readyStatus(
                    s.bookTitles.first, s.usualMinutes);
      case RowNeedsBook():
        status = ParentLoggingCopy.needsBookStatus;
      case RowSubmitting():
        status = ParentLoggingCopy.submitting;
      case RowJustCreatedByMe():
        status = ParentLoggingCopy.createdStatus(
            s.log.minutesRead,
            s.log.titleUnresolved || s.log.bookTitles.isEmpty
                ? 'title to add'
                : s.log.bookTitles.first);
        statusExtra = _InlineTextButton(
          label: ParentLoggingCopy.undoMyQuickLog,
          onPressed: onUndo,
        );
      case RowLoggedByOther():
        status = ParentLoggingCopy.otherStatus(
            s.log.minutesRead, s.log.loggedByDisplay);
      case RowMultiSessions():
        status =
            ParentLoggingCopy.multiStatus(s.sessions, s.totalMinutes);
      case RowClassroomOnly():
        status = ParentLoggingCopy.classroomStatus(s.classroomMinutes);
      case RowOfflinePending():
        status = ParentLoggingCopy.pendingStatus;
      case RowConflict():
        status = ParentLoggingCopy.conflictStatus;
      case RowAccessUnavailable():
        status = ParentLoggingCopy.accessPaused;
      case RowQuickLogDisabled():
        status = '';
    }

    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.firstName,
            style: LumiType.body.copyWith(fontWeight: FontWeight.w700),
          ),
          // Reserved, constant-height status strip: state changes REPLACE its
          // content; they never insert lines, so the row's height is
          // identical in every state (§3.1) and the inline Undo gets a full
          // 44pt target without growing anything (§3.6).
          SizedBox(
            height: ChildLogRow.statusStripHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      status,
                      style: muted,
                      maxLines: dateMismatchNote != null ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (statusExtra != null) ...[
                    const SizedBox(width: 8),
                    statusExtra,
                  ],
                ],
              ),
            ),
          ),
          if (dateMismatchNote != null)
            Text(dateMismatchNote!,
                style: muted.copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// The inline Undo on the status line — deliberately positioned AWAY from
/// the trailing action's rect, filling the reserved status strip so its
/// target is a full 44pt without growing the row.
class _InlineTextButton extends StatelessWidget {
  const _InlineTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: ChildLogRow.statusStripHeight, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Align(
              widthFactor: 1,
              child: Text(
                label,
                style: LumiType.caption.copyWith(
                  color: LumiTokens.red,
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

/// The fixed-width trailing slot: a LABELLED button (never a bare
/// check-circle), a static summary chip, or nothing — content swaps, the
/// slot itself never moves or resizes.
class _TrailingAction extends StatelessWidget {
  const _TrailingAction({
    required this.student,
    required this.state,
    required this.onQuickLog,
    required this.onChooseBook,
    required this.onReview,
    required this.fixedWidth,
  });

  final StudentModel student;
  final ChildLogRowState state;
  final VoidCallback? onQuickLog;
  final VoidCallback? onChooseBook;
  final VoidCallback? onReview;
  final double? fixedWidth;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final Widget child;
    switch (s) {
      case RowReady():
        child = _button(
          label: ParentLoggingCopy.readyAction(s.usualMinutes),
          semanticsLabel: ParentLoggingCopy.semanticsQuickLog(
              s.usualMinutes, student.firstName, s.bookTitles.first),
          onPressed: onQuickLog,
          filled: true,
        );
      case RowNeedsBook():
        child = _button(
          label: ParentLoggingCopy.needsBookAction,
          semanticsLabel:
              '${ParentLoggingCopy.needsBookAction} for ${student.firstName}',
          onPressed: onChooseBook,
          filled: false,
        );
      case RowSubmitting():
        child = _button(
          label: ParentLoggingCopy.submitting,
          semanticsLabel: ParentLoggingCopy.submitting,
          onPressed: null,
          filled: true,
        );
      case RowJustCreatedByMe():
        // Static, NON-interactive chip where the button used to be: a rapid
        // second tap on the same spot does nothing (§3.3 step 3).
        child = _staticChip('${s.log.minutesRead} min logged');
      case RowLoggedByOther():
        child = _button(
          label: ParentLoggingCopy.reviewAction,
          semanticsLabel: ParentLoggingCopy.semanticsRowLogged(
              student.firstName, 1),
          onPressed: onReview,
          filled: false,
        );
      case RowMultiSessions():
        child = _button(
          label: s.sessions > 1
              ? ParentLoggingCopy.reviewSessionsAction
              : ParentLoggingCopy.reviewAction,
          semanticsLabel: ParentLoggingCopy.semanticsRowLogged(
              student.firstName, s.sessions),
          onPressed: onReview,
          filled: false,
        );
      case RowClassroomOnly():
        return _TrailingAction(
          student: student,
          state: s.inner,
          onQuickLog: onQuickLog,
          onChooseBook: onChooseBook,
          onReview: onReview,
          fixedWidth: fixedWidth,
        );
      case RowOfflinePending():
        child = _button(
          label: ParentLoggingCopy.reviewAction,
          semanticsLabel:
              '${student.firstName}, ${ParentLoggingCopy.pendingStatus}. '
              '${ParentLoggingCopy.reviewAction}.',
          onPressed: onReview,
          filled: false,
        );
      case RowConflict():
        child = _button(
          label: ParentLoggingCopy.resolveAction,
          semanticsLabel:
              '${student.firstName}, ${ParentLoggingCopy.conflictStatus}. '
              '${ParentLoggingCopy.resolveAction}.',
          onPressed: onReview,
          filled: true,
        );
      case RowAccessUnavailable():
      case RowQuickLogDisabled():
        child = const SizedBox.shrink();
    }

    return SizedBox(width: fixedWidth, child: Center(child: child));
  }

  Widget _staticChip(String label) => ExcludeSemantics(
        // The info column already announces the logged state; a second,
        // non-interactive copy would just be noise for screen readers.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: LumiTokens.green.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.green,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  Widget _button({
    required String label,
    required String semanticsLabel,
    required VoidCallback? onPressed,
    required bool filled,
  }) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: filled
            ? (onPressed == null
                ? LumiTokens.red.withValues(alpha: 0.35)
                : LumiTokens.red)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: filled
              ? BorderSide.none
              : const BorderSide(color: LumiTokens.red, width: 1.5),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          child: ConstrainedBox(
            // 44pt minimum target (§3.6).
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: LumiType.caption.copyWith(
                    color: filled ? LumiTokens.paper : LumiTokens.red,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Announce a save/undo exactly once and move screen-reader focus along —
/// shared by both quick-log hosts (§3.6).
void announceForAccessibility(BuildContext context, String message) {
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
}
