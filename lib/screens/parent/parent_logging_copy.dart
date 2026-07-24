import '../../data/models/reading_log_model.dart';
import '../../services/reading_log_service.dart';

/// Every user-visible string in the parent quick-logging flow, in one place
/// (docs/PARENT_LOGGING_FLOW_PLAN.md §3.5) so QA can diff copy without
/// hunting through widgets. Functions take the values they interpolate;
/// nothing here reads global state.
class ParentLoggingCopy {
  ParentLoggingCopy._();

  // ── Ready ──────────────────────────────────────────────────────────
  static String readyStatus(String book, int minutes) =>
      '$book · usual $minutes min';

  static String readyStatusMulti(String firstBook, int moreCount, int minutes) =>
      '$firstBook +$moreCount more · usual $minutes min';

  static String readyAction(int minutes) => 'Log $minutes min';

  static String schoolGoal(int minutes, String book) =>
      'School goal: $minutes min · $book';

  // ── Needs book ─────────────────────────────────────────────────────
  static const String needsBookStatus = 'No current book';
  static const String needsBookAction = 'Choose book';

  // ── Submitting ─────────────────────────────────────────────────────
  static const String submitting = 'Logging…';

  // ── Offline pending (PR-F) ─────────────────────────────────────────
  static const String pendingStatus = 'Saved on this phone · not yet shared';
  static const String pendingEdit = 'Edit pending';
  static const String pendingCancel = 'Cancel pending';

  // ── Just created by me ─────────────────────────────────────────────
  static String createdStatus(int minutes, String book) =>
      '$minutes min logged · $book';
  static const String undoMyQuickLog = 'Undo my quick log';
  static const String editThisLog = 'Edit this log';
  static const String undoDone = 'Log removed';

  // ── Logged by someone else / multiple sessions ─────────────────────
  static String otherStatus(int minutes, String name) =>
      '$minutes min logged by $name';
  static String multiStatus(int sessions, int minutes) =>
      '$sessions sessions · $minutes min';
  static const String reviewAction = 'Review';
  static const String reviewSessionsAction = 'Review sessions';

  // ── Classroom-only ─────────────────────────────────────────────────
  static String classroomStatus(int minutes) =>
      'Read at school today · $minutes min';

  // ── Conflict / error (PR-F) ────────────────────────────────────────
  static const String conflictStatus = 'Needs review';
  static const String resolveAction = 'Resolve';
  static const String retryAction = 'Retry';

  // ── Access / gating ────────────────────────────────────────────────
  static const String accessPaused =
      'Logging is paused — contact your school office';

  // ── Slot lost ──────────────────────────────────────────────────────
  static String slotLostNotice(ReadingLogModel winner) =>
      '${winner.loggedByDisplay} logged ${winner.minutesRead} min moments '
      'ago. No new session was added.';
  static const String slotLostNoticeNameless =
      'Tonight is already logged. No new session was added.';

  static String slotLost(QuickSlotTakenException e) {
    final winner = e.existingLog;
    return winner != null ? slotLostNotice(winner) : slotLostNoticeNameless;
  }

  // ── Date disclosure ────────────────────────────────────────────────
  static String dateMismatchNote(String schoolDateDisplay) =>
      'Saving as $schoolDateDisplay (school time)';

  // ── Removal warning (PR-E) ─────────────────────────────────────────
  static String removeLastSessionWarning(String childFirstName) =>
      "This is $childFirstName's only reading tonight. Removing it will "
      'change minutes, reading-night progress and may change the streak.';

  // ── VoiceOver ──────────────────────────────────────────────────────
  static String semanticsQuickLog(int minutes, String child, String book) =>
      'Quick log $minutes minutes for $child, $book.';
  static String semanticsRowReady(String child, String book, int minutes) =>
      '$child, $book, usual $minutes minutes. Opens reading details.';
  static String semanticsRowLogged(String child, int sessions) =>
      sessions > 1
          ? '$child, reading recorded, $sessions sessions, review.'
          : '$child, reading recorded, review.';
  static String semanticsSaved(int minutes, String child) =>
      'Saved $minutes minutes for $child';
}
