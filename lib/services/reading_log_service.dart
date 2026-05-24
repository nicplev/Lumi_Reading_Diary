import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/models/allocation_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import 'firebase_service.dart';
import 'isbn_assignment_service.dart';
import 'notification_service.dart';
import 'offline_service.dart';
import 'widget_data_service.dart';

/// Outcome of a reading-log write.
///
/// Carries the persisted [log], the recomputed student [updatedStats] (null
/// when the stats transaction was skipped — e.g. an offline write), and a
/// [savedOffline] flag so callers can tailor their confirmation copy.
class ReadingLogResult {
  const ReadingLogResult({
    required this.log,
    this.updatedStats,
    this.savedOffline = false,
    this.freezeUsed = false,
  });

  final ReadingLogModel log;
  final Map<String, dynamic>? updatedStats;
  final bool savedOffline;

  /// True when this log spent a streak freeze to bridge a missed day —
  /// drives the shame-free "streak protected" celebration copy (Rec 6).
  final bool freezeUsed;
}

/// Internal result of the stats transaction.
class _StatsUpdate {
  const _StatsUpdate(this.stats, this.freezeUsed);
  final Map<String, dynamic>? stats;
  final bool freezeUsed;
}

/// Single owner of the reading-log write path.
///
/// Before this service the write logic lived inside `LogReadingScreen`, which
/// blocked the one-tap log, notification action, and widget intent from
/// reusing it. Everything that records a reading session now goes through
/// [logReading] / [writeLog] so the Firestore write, the stats transaction,
/// and the home-widget refresh stay in one place.
class ReadingLogService {
  ReadingLogService._() : _firestoreOverride = null;

  /// Test-only constructor that injects a [FirebaseFirestore] (typically a
  /// `FakeFirebaseFirestore`). Production code keeps using [instance].
  @visibleForTesting
  ReadingLogService.forTest({required FirebaseFirestore firestore})
      : _firestoreOverride = firestore;

  static final ReadingLogService instance = ReadingLogService._();

  /// Set on the test-only constructor; null in production so [_firestore]
  /// resolves via the FirebaseService singleton.
  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseService.instance.firestore;

  /// Fallback target/duration when no allocation supplies one.
  static const int _defaultTargetMinutes = 20;

  /// Builds a [ReadingLogModel] from logging inputs without persisting it.
  ///
  /// [minutesRead] and [bookTitles] fall back to allocation-derived defaults,
  /// which is what makes a one-tap [buildQuickLog] possible.
  ReadingLogModel buildLog({
    required StudentModel student,
    required UserModel parent,
    List<AllocationModel> allocations = const [],
    int? minutesRead,
    List<String>? bookTitles,
    ReadingFeeling? feeling,
    List<String> commentSelections = const [],
    String? freeText,
    bool quickLog = false,
  }) {
    final now = DateTime.now();
    final target = allocations.isNotEmpty
        ? allocations.first.targetMinutes
        : _defaultTargetMinutes;
    final titles = _resolveBookTitles(bookTitles, student, allocations);
    final trimmedFreeText = freeText?.trim();
    final hasFreeText = trimmedFreeText != null && trimmedFreeText.isNotEmpty;
    final commentText = _composeComment(commentSelections, trimmedFreeText);

    return ReadingLogModel(
      id: now.millisecondsSinceEpoch.toString(),
      studentId: student.id,
      parentId: parent.id,
      schoolId: student.schoolId,
      classId: student.classId,
      date: now,
      minutesRead: minutesRead ?? target,
      targetMinutes: target,
      status: LogStatus.completed,
      bookTitles: titles,
      notes: hasFreeText ? trimmedFreeText : null,
      childFeeling: feeling,
      parentComment: commentText.isNotEmpty ? commentText : null,
      parentCommentSelections: List<String>.from(commentSelections),
      parentCommentFreeText: hasFreeText ? trimmedFreeText : null,
      createdAt: now,
      allocationId: allocations.isNotEmpty ? allocations.first.id : null,
      loggedByName: parent.fullName,
      loggedByLabel: parent.relationshipLabel,
      metadata: quickLog ? const {'quickLog': true} : null,
    );
  }

  /// Convenience builder for the one-tap log: target minutes, the first
  /// assigned book (or `['Reading']`), completed, `metadata.quickLog = true`.
  ReadingLogModel buildQuickLog({
    required StudentModel student,
    required UserModel parent,
    List<AllocationModel> allocations = const [],
  }) {
    return buildLog(
      student: student,
      parent: parent,
      allocations: allocations,
      quickLog: true,
    );
  }

  /// Builds and persists a reading log in one call. See [writeLog] for the
  /// online/offline behaviour.
  Future<ReadingLogResult> logReading({
    required StudentModel student,
    required UserModel parent,
    List<AllocationModel> allocations = const [],
    int? minutesRead,
    List<String>? bookTitles,
    ReadingFeeling? feeling,
    List<String> commentSelections = const [],
    String? freeText,
    bool quickLog = false,
  }) {
    final log = buildLog(
      student: student,
      parent: parent,
      allocations: allocations,
      minutesRead: minutesRead,
      bookTitles: bookTitles,
      feeling: feeling,
      commentSelections: commentSelections,
      freeText: freeText,
      quickLog: quickLog,
    );
    return writeLog(log, student: student);
  }

  /// Builds and persists a one-tap quick log directly from identifiers.
  ///
  /// Used by code paths that don't hold full [StudentModel] / [UserModel]
  /// objects — the actionable reminder notification (Rec 3) and the iOS
  /// home-screen widget intent drain (Rec 4).
  Future<ReadingLogResult> logQuickFromIds({
    required String studentId,
    required String parentId,
    required String schoolId,
    required String classId,
    int targetMinutes = _defaultTargetMinutes,
    String? bookTitle,
    String? loggedByName,
    String? loggedByLabel,
  }) {
    final now = DateTime.now();
    final titles = (bookTitle != null && bookTitle.trim().isNotEmpty)
        ? <String>[bookTitle.trim()]
        : const <String>['Reading'];
    final log = ReadingLogModel(
      id: now.millisecondsSinceEpoch.toString(),
      studentId: studentId,
      parentId: parentId,
      schoolId: schoolId,
      classId: classId,
      date: now,
      minutesRead: targetMinutes,
      targetMinutes: targetMinutes,
      status: LogStatus.completed,
      bookTitles: titles,
      createdAt: now,
      loggedByName: loggedByName,
      loggedByLabel: loggedByLabel,
      metadata: const {'quickLog': true},
    );
    return writeLog(log);
  }

  /// Persists an already-built [log].
  ///
  /// Online: writes to Firestore, runs the stats transaction, refreshes the
  /// home-screen widget, and returns the recomputed stats. A genuine online
  /// failure rethrows so the caller can surface it.
  ///
  /// Offline: persists to local Hive storage (queued for sync) and skips the
  /// stats transaction — transactions need a server round-trip, and stats are
  /// recomputed when the log syncs.
  ///
  /// [student] is optional: when supplied the home-screen widget is refreshed
  /// immediately; id-only callers (notification / widget intent) omit it and
  /// the widget refreshes on the next app foreground instead.
  Future<ReadingLogResult> writeLog(
    ReadingLogModel log, {
    StudentModel? student,
  }) async {
    if (OfflineService.instance.isOnline) {
      final logData = log.toFirestore();
      // Server timestamp for an accurate audit trail (teachers can see the
      // exact submission time).
      logData['createdAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection('schools')
          .doc(log.schoolId)
          .collection('readingLogs')
          .doc(log.id)
          .set(logData);

      final statsUpdate = await _updateStudentStats(log);

      // Push fresh data to the home-screen widget immediately after the log.
      if (student != null) {
        WidgetDataService.instance.updateAfterLog(student: student, log: log);
      }

      // Rec 3: context-aware notification firing — cancel today's reminder
      // for this child now that they're logged. Fire-and-forget; failures
      // are logged inside the service and never block the write path.
      unawaited(NotificationService.instance
          .refreshReminderForToday(studentId: log.studentId));

      return ReadingLogResult(
        log: log,
        updatedStats: statsUpdate.stats,
        freezeUsed: statsUpdate.freezeUsed,
      );
    }

    // Offline: persist locally and queue for sync.
    final offlineLog = log.copyWith(isOfflineCreated: true);
    await OfflineService.instance.saveReadingLogLocally(offlineLog);
    if (student != null) {
      WidgetDataService.instance
          .updateAfterLog(student: student, log: offlineLog);
    }
    // Same Rec 3 hook applies offline — the user has "done their part" for
    // today, so don't keep nudging them.
    unawaited(NotificationService.instance
        .refreshReminderForToday(studentId: log.studentId));
    return ReadingLogResult(log: offlineLog, savedOffline: true);
  }

  /// Patches a child-feeling onto an already-saved log document.
  ///
  /// Used by the progressive-disclosure prompt on the success screen, where
  /// the feeling is collected after the log is already written.
  Future<void> attachFeeling(
    ReadingLogModel log,
    ReadingFeeling feeling,
  ) async {
    await _logRef(log).update({
      'childFeeling': feeling.toString().split('.').last,
    });
  }

  /// Patches parent-comment fields onto an already-saved log document.
  Future<void> attachComment(
    ReadingLogModel log, {
    List<String> selections = const [],
    String? freeText,
  }) async {
    final trimmed = freeText?.trim();
    final hasFreeText = trimmed != null && trimmed.isNotEmpty;
    final commentText = _composeComment(selections, trimmed);
    await _logRef(log).update({
      'parentCommentSelections': selections,
      'parentCommentFreeText': hasFreeText ? trimmed : null,
      'parentComment': commentText.isNotEmpty ? commentText : null,
    });
  }

  DocumentReference<Map<String, dynamic>> _logRef(ReadingLogModel log) {
    return _firestore
        .collection('schools')
        .doc(log.schoolId)
        .collection('readingLogs')
        .doc(log.id);
  }

  /// Resolves the book titles for a log: explicit titles win; otherwise the
  /// student's first effective assigned book; otherwise a generic fallback.
  List<String> _resolveBookTitles(
    List<String>? explicit,
    StudentModel student,
    List<AllocationModel> allocations,
  ) {
    final cleaned = explicit
            ?.map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList() ??
        const <String>[];
    if (cleaned.isNotEmpty) return cleaned;

    for (final allocation in allocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(student.id)) {
        final title = item.title.trim();
        if (title.isNotEmpty) {
          return [IsbnAssignmentService.sanitizeDisplayTitle(title)];
        }
      }
    }
    return const ['Reading'];
  }

  /// Joins comment chips and free-text into the denormalized `parentComment`
  /// string (mirrors the wizard's original composition).
  String _composeComment(List<String> selections, String? freeText) {
    final chips = selections.join('. ');
    final notes = freeText?.trim() ?? '';
    if (chips.isNotEmpty && notes.isNotEmpty) return '$chips. $notes';
    return chips.isNotEmpty ? chips : notes;
  }

  /// Recomputes `students/{id}.stats` inside a transaction.
  ///
  /// Streak handling is shame-free (Rec 6): a single missed day spends a
  /// streak freeze instead of resetting the streak, and a fresh freeze is
  /// earned every 7 consecutive days (capped at [StudentStats.defaultStreakFreezes]).
  Future<_StatsUpdate> _updateStudentStats(ReadingLogModel log) async {
    try {
      final studentRef = _firestore
          .collection('schools')
          .doc(log.schoolId)
          .collection('students')
          .doc(log.studentId);

      Map<String, dynamic>? newStats;
      bool freezeUsed = false;

      await _firestore.runTransaction((transaction) async {
        // Reset per-attempt — a transaction closure may run more than once.
        freezeUsed = false;
        final studentDoc = await transaction.get(studentRef);

        if (studentDoc.exists) {
          final data = studentDoc.data() as Map<String, dynamic>;
          final stats = data['stats'] as Map<String, dynamic>? ?? {};

          final currentStreak = stats['currentStreak'] ?? 0;
          final longestStreak = stats['longestStreak'] ?? 0;
          final totalMinutesRead = stats['totalMinutesRead'] ?? 0;
          final totalBooksRead = stats['totalBooksRead'] ?? 0;
          final totalReadingDays = stats['totalReadingDays'] ?? 0;

          int freezesAvailable = stats['streakFreezesAvailable'] ??
              StudentStats.defaultStreakFreezes;
          int freezesUsedTotal = stats['streakFreezesUsed'] ?? 0;
          DateTime? freezeEarnedDate =
              stats['streakFreezeLastEarnedDate'] != null
                  ? (stats['streakFreezeLastEarnedDate'] as Timestamp).toDate()
                  : null;

          final lastReadingDate = stats['lastReadingDate'] != null
              ? (stats['lastReadingDate'] as Timestamp).toDate().toLocal()
              : null;

          int newStreak = 1;
          bool isNewDay = true;
          if (lastReadingDate != null) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final lastDay = DateTime(
              lastReadingDate.year,
              lastReadingDate.month,
              lastReadingDate.day,
            );
            final calendarDaysDiff = today.difference(lastDay).inDays;

            if (calendarDaysDiff == 1) {
              newStreak = currentStreak + 1;
            } else if (calendarDaysDiff == 0) {
              newStreak = currentStreak;
              isNewDay = false; // Same day — don't double-count
            } else if (calendarDaysDiff == 2 && freezesAvailable > 0) {
              // Exactly one day missed — spend a freeze to protect the streak.
              newStreak = currentStreak + 1;
              freezesAvailable -= 1;
              freezesUsedTotal += 1;
              freezeUsed = true;
            }
            // More than one day missed (or no freeze) → newStreak resets to 1.
          }

          // Earn a freeze every 7 consecutive days, capped at the default.
          if (isNewDay &&
              newStreak > 0 &&
              newStreak % 7 == 0 &&
              freezesAvailable < StudentStats.defaultStreakFreezes) {
            freezesAvailable += 1;
            freezeEarnedDate = DateTime.now();
          }

          final newTotalDays =
              isNewDay ? totalReadingDays + 1 : totalReadingDays;

          newStats = {
            'totalMinutesRead': totalMinutesRead + log.minutesRead,
            'totalBooksRead': totalBooksRead + log.bookTitles.length,
            'currentStreak': newStreak,
            'longestStreak':
                newStreak > longestStreak ? newStreak : longestStreak,
            'lastReadingDate': FieldValue.serverTimestamp(),
            'totalReadingDays': newTotalDays,
            'averageMinutesPerDay': (totalMinutesRead + log.minutesRead) /
                (newTotalDays > 0 ? newTotalDays : 1),
            'streakFreezesAvailable': freezesAvailable,
            'streakFreezesUsed': freezesUsedTotal,
            'streakFreezeLastEarnedDate': freezeEarnedDate != null
                ? Timestamp.fromDate(freezeEarnedDate)
                : null,
          };

          transaction.update(studentRef, {'stats': newStats});
        }
      });

      return _StatsUpdate(newStats, freezeUsed);
    } catch (e) {
      debugPrint('Error updating student stats: $e');
      return const _StatsUpdate(null, false);
    }
  }
}
