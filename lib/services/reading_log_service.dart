import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/services/service_status_controller.dart';
import '../core/utils/school_time.dart';
import '../data/models/allocation_model.dart';
import '../data/models/log_comment_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import 'firebase_service.dart';
import 'comprehension_audio_service.dart';
import 'isbn_assignment_service.dart';
import 'offline_service.dart';
import 'widget_data_service.dart';

/// Outcome of a reading-log write.
///
/// Carries the persisted [log], a display-only [updatedStats] **preview** for
/// the success screen (null for offline writes), and a [savedOffline] flag so
/// callers can tailor their confirmation copy. The authoritative stats are
/// written by the aggregateStudentStats Cloud Function; the preview just lets
/// the celebration render instantly before the server reconciles.
class ReadingLogResult {
  const ReadingLogResult({
    required this.log,
    this.updatedStats,
    this.savedOffline = false,
    this.restDayApplied = false,
  });

  final ReadingLogModel log;

  /// Optimistic, display-only preview of the student's stats after this log.
  /// Not persisted — the Cloud Function is the single source of truth.
  final Map<String, dynamic>? updatedStats;
  final bool savedOffline;

  /// True when this log bridged a missed night via rest-day tolerance —
  /// drives the shame-free "rest day, your streak keeps going" celebration.
  final bool restDayApplied;
}

class QuickLoggingDisabledException implements Exception {
  const QuickLoggingDisabledException();

  @override
  String toString() => 'Quick logging is disabled for this school';
}

/// Thrown when a one-tap quick log is attempted with no resolvable book:
/// no effective assigned books and no pinned current book. The UI responds
/// with the "Choose book" state — a generic placeholder title is NEVER
/// fabricated or persisted (persona principle #5).
class NoCurrentBookException implements Exception {
  const NoCurrentBookException();

  @override
  String toString() => 'No current book to attribute the quick log to';
}

/// Thrown when the day's canonical home quick slot is already held, so the
/// attempted quick log wrote NOTHING. Carries what is known about the winner
/// so the UI can say "Jordan logged 20 min moments ago. No new session was
/// added." — [existingLog] is best-effort (null if unreadable).
class QuickSlotTakenException implements Exception {
  const QuickSlotTakenException({
    required this.occurredOn,
    this.byUid,
    this.existingLogId,
    this.existingLog,
  });

  final String occurredOn;
  final String? byUid;
  final String? existingLogId;
  final ReadingLogModel? existingLog;

  @override
  String toString() =>
      'Home quick session for $occurredOn already logged; nothing was added';
}

/// Thrown when the child's access entitlement is not live. Belt-and-braces
/// behind the route-level AccessLockedScreen gate: no local write may be
/// queued that could later bypass revoked access (rules are the authority
/// server-side; this stops the client queueing doomed work).
class StudentAccessInactiveException implements Exception {
  const StudentAccessInactiveException();

  @override
  String toString() => 'Student access is not active';
}

/// Editing an existing session needs a live connection (the offline drain's
/// create-once policy would silently drop a queued edit). The UI shows
/// "reconnect to edit" copy instead of failing quietly.
class ReadingLogEditOfflineException implements Exception {
  const ReadingLogEditOfflineException();

  @override
  String toString() => 'Editing a session requires a connection';
}

/// Internal result of the stats preview.
class _StatsUpdate {
  const _StatsUpdate(this.stats, this.restDayApplied);
  final Map<String, dynamic>? stats;
  final bool restDayApplied;
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

  /// Generates an unguessable, idempotency-safe reading-log document ID.
  ///
  /// Timestamp IDs collide when two devices submit in the same millisecond and
  /// reveal creation order. A 128-bit cryptographically random value avoids
  /// both problems while remaining stable when an offline write is retried.
  static String generateLogId() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

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
    String? id,
    String? comprehensionAudioPath,
    int? comprehensionAudioDurationSec,
    String? schoolTimezone,
    String? occurredOn,
    List<Map<String, dynamic>>? books,
  }) {
    final now = DateTime.now();
    final target = allocations.isNotEmpty
        ? allocations.first.targetMinutes
        : _defaultTargetMinutes;
    final titles = _resolveBookTitles(bookTitles, student, allocations);
    // A quick log must have at least one explicitly resolved book — the UI
    // shows "Choose book" instead of writing a fabricated title.
    if (quickLog && titles.isEmpty) throw const NoCurrentBookException();
    final trimmedFreeText = freeText?.trim();
    final hasFreeText = trimmedFreeText != null && trimmedFreeText.isNotEmpty;
    final commentText = _composeComment(commentSelections, trimmedFreeText);

    return ReadingLogModel(
      id: id ?? generateLogId(),
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
      loggedByRole: LoggedByRole.parent,
      // Stamped at tap time in the SCHOOL's timezone so the stated day
      // survives offline-before-midnight syncs; an explicit [occurredOn]
      // (Yesterday backdating, flag-gated in the detailed flow) wins.
      occurredOn:
          occurredOn ?? SchoolTime.localDateString(now, schoolTimezone),
      // A parent session is home reading by definition (rules enforce it).
      context: 'home',
      books: books,
      metadata: quickLog ? const {'quickLog': true} : null,
      comprehensionAudioPath: comprehensionAudioPath,
      comprehensionAudioDurationSec: comprehensionAudioDurationSec,
      // Always false at create time; flipped after the Storage upload lands.
      comprehensionAudioUploaded: false,
    );
  }

  /// Convenience builder for the one-tap log: target minutes, the union of
  /// effective assigned books, completed, `metadata.quickLog = true`.
  /// Throws [NoCurrentBookException] when no book can be resolved — the
  /// caller shows "Choose book"; nothing is fabricated.
  ReadingLogModel buildQuickLog({
    required StudentModel student,
    required UserModel parent,
    List<AllocationModel> allocations = const [],
    String? schoolTimezone,
  }) {
    return buildLog(
      student: student,
      parent: parent,
      allocations: allocations,
      quickLog: true,
      schoolTimezone: schoolTimezone,
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
    String? id,
    String? comprehensionAudioPath,
    int? comprehensionAudioDurationSec,
    String? schoolTimezone,
    String? occurredOn,
    bool? claimQuickSlot,
    List<Map<String, dynamic>>? books,
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
      id: id,
      comprehensionAudioPath: comprehensionAudioPath,
      comprehensionAudioDurationSec: comprehensionAudioDurationSec,
      schoolTimezone: schoolTimezone,
      occurredOn: occurredOn,
      books: books,
    );
    return writeLog(log, student: student, claimQuickSlot: claimQuickSlot);
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
    String? schoolTimezone,
  }) {
    final now = DateTime.now();
    // Id-only callers must supply the book explicitly — with no allocations
    // in hand there is nothing legitimate to attribute the session to, and a
    // placeholder title is never fabricated (persona principle #5). Callers
    // should deep-link into the app's chooser instead.
    final trimmedTitle = bookTitle?.trim();
    if (trimmedTitle == null || trimmedTitle.isEmpty) {
      throw const NoCurrentBookException();
    }
    final log = ReadingLogModel(
      id: generateLogId(),
      studentId: studentId,
      parentId: parentId,
      schoolId: schoolId,
      classId: classId,
      date: now,
      minutesRead: targetMinutes,
      targetMinutes: targetMinutes,
      status: LogStatus.completed,
      bookTitles: <String>[trimmedTitle],
      createdAt: now,
      loggedByName: loggedByName,
      loggedByLabel: loggedByLabel,
      loggedByRole: LoggedByRole.parent,
      occurredOn: SchoolTime.localDateString(now, schoolTimezone),
      context: 'home',
      metadata: const {'quickLog': true},
    );
    return writeLog(log);
  }

  /// Persists a reading log entered by a teacher on behalf of a student
  /// whose carer cannot use the app. `parentId` carries the teacher's UID
  /// (the creator) so existing ownership rules keep working; `loggedByRole`
  /// = `teacher` is the proxy signal that consumers filter on. Reuses the
  /// regular [writeLog] path so offline + stats handling stays identical to
  /// parent-side logs.
  Future<ReadingLogResult> logReadingAsTeacher({
    required UserModel teacher,
    required StudentModel student,
    required DateTime date,
    required int minutesRead,
    required List<String> bookTitles,
    String? notes,
    String? allocationId,
    int targetMinutes = _defaultTargetMinutes,
    bool isClassroomContext = false,
  }) {
    final now = DateTime.now();
    final cleanedTitles =
        bookTitles.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    // The sheet's _canSave already requires a title; never fabricate one.
    if (cleanedTitles.isEmpty) {
      throw ArgumentError.value(
          bookTitles, 'bookTitles', 'must contain at least one title');
    }
    final trimmedNotes = notes?.trim();

    // The teacher picked a calendar DATE, not an instant — take its
    // components directly so a device timezone can't shift the stated day.
    final occurredOn = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final log = ReadingLogModel(
      id: generateLogId(),
      studentId: student.id,
      parentId: teacher.id,
      schoolId: student.schoolId,
      classId: student.classId,
      date: date,
      minutesRead: minutesRead,
      targetMinutes: targetMinutes,
      status: LogStatus.completed,
      bookTitles: cleanedTitles,
      notes: (trimmedNotes != null && trimmedNotes.isNotEmpty)
          ? trimmedNotes
          : null,
      createdAt: now,
      allocationId: allocationId,
      loggedByName: teacher.fullName,
      loggedByLabel: 'Logged by ${teacher.fullName}',
      loggedByRole: LoggedByRole.teacher,
      occurredOn: occurredOn,
      // Explicit teacher choice: 'classroom' shows on the family's Home as
      // school reading without satisfying the home slot; 'home' is the
      // original proxy semantics (#39).
      context: isClassroomContext ? 'classroom' : 'home',
    );
    return writeLog(log, student: student);
  }

  /// Persists an already-built [log].
  ///
  /// Online: writes the log to Firestore, refreshes the home-screen widget, and
  /// returns a display-only stats preview for the celebration. The authoritative
  /// stats are recomputed by the aggregateStudentStats Cloud Function (the
  /// single source of truth) — the client no longer persists computed stats. A
  /// genuine online failure rethrows so the caller can surface it.
  ///
  /// Offline: persists to local Hive storage (queued for sync). Stats are
  /// computed by the Cloud Function when the queued log lands in Firestore.
  ///
  /// [student] is optional: when supplied the home-screen widget is refreshed
  /// immediately; id-only callers (notification / widget intent) omit it and
  /// the widget refreshes on the next app foreground instead.
  /// How long the interactive online write waits for a SERVER ack before
  /// falling back to the offline queue. With offline persistence enabled, a
  /// `set()` Future resolves only on server ack — on "healthy-looking but
  /// dead" school wifi (the status probe refreshes every ~600s, so a stale
  /// healthy verdict is possible) it used to hang the save spinner forever.
  static const Duration _onlineWriteAckTimeout = Duration(seconds: 15);

  Future<ReadingLogResult> writeLog(
    ReadingLogModel log, {
    StudentModel? student,
    bool? claimQuickSlot,
  }) async {
    await _guardQuickLoggingAllowed(log);

    // Belt-and-braces behind the route gate: never queue a local write that
    // could later bypass revoked access. Rules are the server-side authority.
    if (student != null && !student.hasActiveAccess) {
      throw const StudentAccessInactiveException();
    }

    // The one-tap quick log claims the day's canonical home slot so co-
    // guardians and second devices can't duplicate the DEFAULT session.
    // Explicit "Add another session" writes pass claimQuickSlot: false.
    final claimSlot = claimQuickSlot ??
        (log.isQuickLog &&
            log.loggedByRole != LoggedByRole.teacher &&
            log.occurredOn != null);

    if (ServiceStatusController.instance.current.canWriteToFirebase) {
      final logData = log.toFirestore();
      // Server timestamp for an accurate audit trail (teachers can see the
      // exact submission time).
      logData['createdAt'] = FieldValue.serverTimestamp();
      // Audio receipt fields are server-owned. The recording is uploaded only
      // after this log exists, then confirmComprehensionAudioUpload verifies the
      // canonical object and stamps these fields with Admin SDK privileges.
      logData.remove('comprehensionAudioPath');
      logData.remove('comprehensionAudioDurationSec');
      logData.remove('comprehensionAudioUploaded');
      logData.remove('comprehensionAudioUploadedAt');
      logData.remove('comprehensionAudioObjectGeneration');
      logData.remove('comprehensionQuestionText');
      logData.remove('comprehensionAudioReviewStatus');
      logData.remove('comprehensionAudioReviewedAt');
      logData.remove('comprehensionAudioReviewedGeneration');
      logData.remove('teacherComment');
      logData.remove('commentedAt');
      logData.remove('commentedBy');
      logData.remove('lastCommentPreview');
      logData.remove('lastCommentAt');
      logData.remove('lastCommentByRole');
      logData.remove('commentsViewedAt');

      try {
        if (claimSlot) {
          // Fast-path courtesy check so the common "co-guardian already
          // logged" case reads the winner instead of burning a doomed batch.
          // The race window that remains is arbitrated by rules: the slot is
          // create-only, so the losing batch is rejected wholesale and the
          // loser wrote NOTHING.
          final existingSlot = await _getQuickSlot(log);
          if (existingSlot != null) {
            throw await _slotTakenException(log, existingSlot);
          }
          final batch = _firestore.batch();
          batch.set(_logRef(log), logData);
          batch.set(_quickSlotRef(log), {
            'logId': log.id,
            'byUid': log.parentId,
            'createdAt': FieldValue.serverTimestamp(),
          });
          try {
            await batch.commit().timeout(_onlineWriteAckTimeout);
          } on FirebaseException catch (e) {
            if (e.code != 'permission-denied') rethrow;
            // A denied batch is either the slot race (someone won between
            // our check and commit) or a genuine authz failure. Re-read the
            // slot to tell them apart.
            final slotNow = await _getQuickSlot(log);
            if (slotNow != null) {
              throw await _slotTakenException(log, slotNow);
            }
            rethrow;
          }
        } else {
          await _logRef(log).set(logData).timeout(_onlineWriteAckTimeout);
        }

        final statsUpdate = await _previewStatsAfterLog(log);

        // Push fresh data to the home-screen widget immediately after the log.
        // A teacher's proxy-log refreshes the teacher widget; a parent's, the
        // parent widget.
        if (student != null) {
          if (log.loggedByRole == LoggedByRole.teacher) {
            WidgetDataService.instance
                .updateAfterTeacherLog(student: student, log: log);
          } else {
            WidgetDataService.instance
                .updateAfterLog(student: student, log: log);
          }
        }

        return ReadingLogResult(
          log: log,
          updatedStats: statsUpdate.stats,
          restDayApplied: statsUpdate.restDayApplied,
        );
      } on TimeoutException {
        // No server ack in time — treat the connection as down and fall
        // through to the offline queue, so the family sees "saved, will
        // sync" instead of an endless spinner. Safe double-delivery: the
        // timed-out mutation may still land later from Firestore's internal
        // queue, but the offline replay `set()`s the SAME doc id with the
        // same content, so the overwrite is idempotent and the stats
        // trigger sees a zero-delta update. Non-timeout errors (e.g.
        // permission-denied) still rethrow so the caller surfaces them.
        debugPrint(
            'writeLog: no server ack in ${_onlineWriteAckTimeout.inSeconds}s '
            '— queueing offline');
      }
    }

    // Offline (or the online write never acked): persist locally and queue.
    // The slot claim rides along so the drain replays the same atomic batch;
    // a slot taken while we were offline surfaces as an explicit conflict for
    // the guardian to resolve — never a silent overwrite or drop.
    final offlineLog = log.copyWith(isOfflineCreated: true);
    await OfflineService.instance
        .saveReadingLogLocally(offlineLog, claimQuickSlot: claimSlot);
    if (student != null) {
      if (offlineLog.loggedByRole == LoggedByRole.teacher) {
        WidgetDataService.instance
            .updateAfterTeacherLog(student: student, log: offlineLog);
      } else {
        WidgetDataService.instance
            .updateAfterLog(student: student, log: offlineLog);
      }
    }
    return ReadingLogResult(log: offlineLog, savedOffline: true);
  }

  Future<void> _guardQuickLoggingAllowed(ReadingLogModel log) async {
    if (!log.isQuickLog || log.loggedByRole == LoggedByRole.teacher) return;
    final enabled = await _quickLoggingEnabled(log.schoolId);
    if (!enabled) throw const QuickLoggingDisabledException();
  }

  Future<bool> _quickLoggingEnabled(String schoolId) async {
    if (schoolId.isEmpty) return true;
    try {
      final doc = await _firestore.collection('schools').doc(schoolId).get();
      final data = doc.data();
      if (data == null) return true;
      final settings = data['settings'];
      if (settings is! Map) return true;
      final quickLogging = settings['quickLogging'];
      if (quickLogging is! Map) return true;
      final enabled = quickLogging['enabled'];
      return enabled is bool ? enabled : true;
    } catch (e) {
      debugPrint('quickLoggingEnabled check failed for $schoolId: $e');
      return true;
    }
  }

  /// Patches a child-feeling onto an already-saved log document.
  ///
  /// Used by the progressive-disclosure prompt on the success screen, where
  /// the feeling is collected after the log is already written.
  Future<void> attachFeeling(
    ReadingLogModel log,
    ReadingFeeling feeling,
  ) async {
    final feelingName = feeling.toString().split('.').last;
    // Offline: queue it (like attachComment / attachComprehension) so the
    // child's feeling isn't silently lost when there's no connection — it was
    // the only attach* method without an offline fallback.
    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      await OfflineService.instance.enqueueChildFeeling(
        logId: log.id,
        schoolId: log.schoolId,
        feeling: feelingName,
      );
      return;
    }
    await _logRef(log).update({'childFeeling': feelingName});
  }

  /// Patches parent-comment fields onto an already-saved log document.
  ///
  /// Queues the update locally when Firebase isn't writable so a parent
  /// can leave a comment offline and have it land when reconnection
  /// happens, rather than losing what they typed.
  Future<void> attachComment(
    ReadingLogModel log, {
    List<String> selections = const [],
    String? freeText,
  }) async {
    final trimmed = freeText?.trim();
    final hasFreeText = trimmed != null && trimmed.isNotEmpty;
    final commentText = _composeComment(selections, trimmed);

    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      await OfflineService.instance.enqueueParentComment(
        logId: log.id,
        schoolId: log.schoolId,
        selections: selections,
        freeText: hasFreeText ? trimmed : null,
        composedComment: commentText,
      );
      return;
    }

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

  /// The day's canonical home quick-slot document for [log]'s student:
  /// `schools/{schoolId}/students/{studentId}/quickSlots/{occurredOn}`.
  DocumentReference<Map<String, dynamic>> _quickSlotRef(ReadingLogModel log) {
    return _firestore
        .collection('schools')
        .doc(log.schoolId)
        .collection('students')
        .doc(log.studentId)
        .collection('quickSlots')
        .doc(log.occurredOn);
  }

  /// Reads the quick slot for [log]'s day; null when free (or unreadable —
  /// the batch commit + rules remain the authority in that case).
  Future<Map<String, dynamic>?> _getQuickSlot(ReadingLogModel log) async {
    try {
      final snap =
          await _quickSlotRef(log).get().timeout(_onlineWriteAckTimeout);
      return snap.exists ? snap.data() : null;
    } on FirebaseException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  /// Builds the "no new session was added" outcome, best-effort enriching it
  /// with the winning session so the UI can name the guardian and minutes.
  Future<QuickSlotTakenException> _slotTakenException(
    ReadingLogModel attempted,
    Map<String, dynamic> slot,
  ) async {
    final existingLogId = slot['logId'] as String?;
    ReadingLogModel? existingLog;
    if (existingLogId != null) {
      try {
        final snap = await _firestore
            .collection('schools')
            .doc(attempted.schoolId)
            .collection('readingLogs')
            .doc(existingLogId)
            .get()
            .timeout(_onlineWriteAckTimeout);
        if (snap.exists) existingLog = ReadingLogModel.fromFirestore(snap);
      } catch (_) {
        // Display degrades to "already logged" without names/minutes.
      }
    }
    return QuickSlotTakenException(
      occurredOn: attempted.occurredOn ?? '',
      byUid: slot['byUid'] as String?,
      existingLogId: existingLogId,
      existingLog: existingLog,
    );
  }

  /// Content-edits a session the CALLER created (owner-scoped by rules).
  ///
  /// The editable field set mirrors `contentUpdateIsValid` in
  /// firestore.rules: minutes, books, notes, feeling, parent comments —
  /// never the date (`occurredOn`/`date` are immutable; a wrong-day fix is
  /// remove + re-log). `editedAt` is stamped server-side for provenance.
  ///
  /// Online-only for now: the offline drain treats an existing doc as a
  /// create-once receipt, so a queued edit would be silently dropped —
  /// callers surface "reconnect to edit" instead (PR-F extends the drain).
  Future<ReadingLogModel> updateOwnLog(
    ReadingLogModel log, {
    int? minutesRead,
    List<String>? bookTitles,
    String? notes,
    ReadingFeeling? feeling,
  }) async {
    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      throw const ReadingLogEditOfflineException();
    }
    final cleanedTitles = bookTitles
        ?.map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final trimmedNotes = notes?.trim();

    final updates = <String, dynamic>{
      if (minutesRead != null) 'minutesRead': minutesRead,
      if (cleanedTitles != null) 'bookTitles': cleanedTitles,
      if (cleanedTitles != null && cleanedTitles.isNotEmpty)
        'titleUnresolved': false,
      if (notes != null)
        'notes': trimmedNotes!.isEmpty ? FieldValue.delete() : trimmedNotes,
      if (feeling != null)
        'childFeeling': feeling.toString().split('.').last,
      'editedAt': FieldValue.serverTimestamp(),
    };
    await _logRef(log).update(updates).timeout(_onlineWriteAckTimeout);

    final updated = log.copyWith(
      minutesRead: minutesRead,
      bookTitles: cleanedTitles,
      notes: notes == null ? null : (trimmedNotes!.isEmpty ? null : trimmedNotes),
      childFeeling: feeling,
      titleUnresolved: (cleanedTitles != null && cleanedTitles.isNotEmpty)
          ? false
          : null,
      // Local approximation of the server-pinned value, for instant display.
      editedAt: DateTime.now(),
    );
    await OfflineService.instance.saveReadingLogCacheOnly(updated);
    return updated;
  }

  /// Counts the student's HOME sessions on [occurredOn] (school-local day) —
  /// powers the "removing the only qualifying session" warning (§5.3).
  Future<int> countHomeSessionsOn({
    required String schoolId,
    required String studentId,
    required String occurredOn,
    required String timezone,
  }) async {
    final range = SchoolTime.utcRangeForLocalDay(occurredOn, timezone);
    // ±1-day query window + client-side occurredOn bucketing, matching the
    // Home row and the server's resolveOccurrenceDate.
    final snap = await _firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingLogs')
        .where('studentId', isEqualTo: studentId)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(
                range.startInclusive.subtract(const Duration(days: 1))))
        .where('date',
            isLessThan: Timestamp.fromDate(
                range.endExclusive.add(const Duration(days: 1))))
        .get();
    return snap.docs
        .map(ReadingLogModel.fromFirestore)
        .where((log) =>
            log.isHomeContext &&
            (log.occurredOn ??
                    SchoolTime.localDateString(log.date, timezone)) ==
                occurredOn)
        .length;
  }

  /// Deletes a session the CALLER created — the undo / remove-my-session
  /// primitive. Targets exactly [log] by ID; when this log holds the day's
  /// quick slot the slot is freed in the same batch so the day's default
  /// session becomes claimable again immediately. Dependent data (comments,
  /// audio, AI evals) is cleaned server-side by onReadingLogDeleted.
  ///
  /// Offline: queues the delete (the drain confirms it server-side; the
  /// server cascade frees the slot when it lands) and removes the local copy.
  Future<void> deleteOwnLog(ReadingLogModel log) async {
    if (ServiceStatusController.instance.current.canWriteToFirebase) {
      try {
        final batch = _firestore.batch();
        batch.delete(_logRef(log));
        if (log.occurredOn != null) {
          final slot = await _getQuickSlot(log);
          if (slot != null && slot['logId'] == log.id) {
            batch.delete(_quickSlotRef(log));
          }
        }
        await batch.commit().timeout(_onlineWriteAckTimeout);
        await OfflineService.instance.removeLocalReadingLog(log.id);
        return;
      } on TimeoutException {
        debugPrint('deleteOwnLog: no server ack — queueing offline delete');
      }
    }
    await OfflineService.instance.enqueueReadingLogDelete(log);
  }

  /// Builds the private pending-upload path for an untrusted recording.
  /// The backend decodes/transcodes this object and alone writes the separate
  /// `comprehension_audio/{logId}.m4a` teacher-playback object.
  static String comprehensionAudioUploadStoragePath({
    required String schoolId,
    required String logId,
  }) =>
      'comprehension_audio_uploads/$schoolId/$logId.m4a';

  /// Uploads the comprehension recording from [localFilePath] to the Storage
  /// path on [log], then patches the log doc to set
  /// `comprehensionAudioUploaded: true`. The temp file is removed after a
  /// confirmed update (best-effort).
  ///
  /// Throws on Storage or Firestore failure — the caller is expected to
  /// queue the upload via [OfflineService.enqueueComprehensionAudioUpload]
  /// when this throws so retries happen with backoff.
  /// [onProgress] receives 0..1 as bytes reach Storage. It is only a
  /// fraction of the wall-clock wait — the confirm callable that follows
  /// decodes and transcodes server-side with no progress to report — so
  /// callers should reserve part of any progress bar for that leg rather
  /// than treating 1.0 here as "done".
  Future<void> uploadComprehensionAudio({
    required ReadingLogModel log,
    required String localFilePath,
    void Function(double fraction)? onProgress,
  }) async {
    final storagePath = comprehensionAudioUploadStoragePath(
      schoolId: log.schoolId,
      logId: log.id,
    );
    final file = File(localFilePath);
    if (!file.existsSync()) {
      throw const ComprehensionAudioMissingException();
    }

    final task = FirebaseStorage.instance.ref(storagePath).putFile(
          file,
          SettableMetadata(
            contentType: 'audio/mp4',
            customMetadata: {
              'uploadedAt': DateTime.now().toUtc().toIso8601String(),
              'durationSec': '${log.comprehensionAudioDurationSec ?? 0}',
              'schoolId': log.schoolId,
              'logId': log.id,
              'ownerUid': log.parentId,
              'studentId': log.studentId,
            },
          ),
        );

    StreamSubscription<TaskSnapshot>? progressSub;
    if (onProgress != null) {
      progressSub = task.snapshotEvents.listen(
        (snapshot) {
          final total = snapshot.totalBytes;
          if (total > 0) {
            onProgress(snapshot.bytesTransferred / total);
          }
        },
        // Never let a progress listener be the thing that fails an upload —
        // the await below is the real error path.
        onError: (_) {},
      );
    }

    try {
      await task;
    } finally {
      await progressSub?.cancel();
    }

    await ComprehensionAudioService().confirmUpload(
      schoolId: log.schoolId,
      logId: log.id,
      durationSec: log.comprehensionAudioDurationSec ?? 0,
    );

    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best-effort: the temp dir gets purged by the OS eventually.
    }
  }

  /// Attaches a comprehension recording to an already-saved log — the
  /// success-screen progressive-disclosure path for one-tap logs, mirroring
  /// [attachFeeling] / [attachComment]. Stamps the Storage path + duration onto
  /// the doc, then uploads the audio. Falls back to the offline upload queue on
  /// failure (or when Firebase isn't writable) so a recording is never lost.
  Future<void> attachComprehension(
    ReadingLogModel log, {
    required String localFilePath,
    required int durationSec,
  }) async {
    final storagePath = comprehensionAudioUploadStoragePath(
      schoolId: log.schoolId,
      logId: log.id,
    );

    Future<void> queue() =>
        OfflineService.instance.enqueueComprehensionAudioUpload(
          logId: log.id,
          schoolId: log.schoolId,
          studentId: log.studentId,
          storagePath: storagePath,
          localFilePath: localFilePath,
          durationSec: durationSec,
        );

    // Offline: the drain stamps the path + duration and flips the uploaded
    // flag once it lands, so just preserve the recording in the queue.
    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      await queue();
      return;
    }

    final patched = log.copyWith(
      comprehensionAudioPath: storagePath,
      comprehensionAudioDurationSec: durationSec,
      comprehensionAudioUploaded: false,
    );
    try {
      await uploadComprehensionAudio(
          log: patched, localFilePath: localFilePath);
    } catch (_) {
      await queue();
    }
  }

  /// Live comment thread for a log, oldest message first. Powers the in-app
  /// conversation view for both parents and teachers.
  ///
  /// The `studentId` equality filter keeps parent queries scoped to one linked
  /// child. Rules additionally load the parent log and bind every comment to
  /// its authoritative child, carer and class.
  ///
  /// Ordering is done client-side instead of via `orderBy('createdAt')` so the
  /// equality filter doesn't pull in a composite index, and so a just-sent
  /// comment whose server timestamp hasn't resolved yet (null → now) still
  /// sorts to the bottom rather than jumping to the top.
  Stream<List<LogCommentModel>> commentsStream(ReadingLogModel log) {
    return _logRef(log)
        .collection('comments')
        .where('studentId', isEqualTo: log.studentId)
        .snapshots()
        .map((snap) {
      final comments = snap.docs.map(LogCommentModel.fromFirestore).toList();
      comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return comments;
    });
  }

  /// Posts a comment to a log's thread and refreshes the denormalized "last
  /// comment" preview on the log so history lists update without reading the
  /// subcollection. The teacher→parent push and the legacy `teacherComment`
  /// mirror are handled server-side by the `onCommentCreated` Cloud Function.
  ///
  /// Queues the write locally when Firebase isn't writable so a comment typed
  /// offline lands on reconnect (the drain creates the log first if needed).
  /// Posts a comment. Returns `true` when it was queued OFFLINE (so the caller
  /// can tell the user it will send later) and `false` when written online.
  /// Throws on an online write failure so the caller can surface an error.
  Future<bool> addComment(
    ReadingLogModel log, {
    required String body,
    required CommentAuthorRole authorRole,
    required String authorId,
    required String authorName,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;

    final roleName = authorRole.toString().split('.').last;
    final commentRef = _logRef(log).collection('comments').doc();

    if (!ServiceStatusController.instance.current.canWriteToFirebase) {
      await OfflineService.instance.enqueueCommentReply(
        logId: log.id,
        schoolId: log.schoolId,
        commentId: commentRef.id,
        authorId: authorId,
        authorRole: roleName,
        authorName: authorName,
        body: trimmed,
        studentId: log.studentId,
        parentId: log.parentId,
      );
      return true;
    }

    final comment = LogCommentModel(
      id: commentRef.id,
      authorId: authorId,
      authorRole: authorRole,
      authorName: authorName,
      body: trimmed,
      createdAt: DateTime.now(), // server timestamp wins on write
      studentId: log.studentId,
      parentId: log.parentId,
    );

    final batch = _firestore.batch();
    batch.set(commentRef, comment.toFirestore());
    batch.update(_logRef(log), {
      'lastCommentPreview': trimmed,
      'lastCommentAt': FieldValue.serverTimestamp(),
      'lastCommentByRole': roleName,
    });
    await batch.commit();
    return false;
  }

  /// Marks a log's thread as seen for [uid] (clears the unread badge).
  /// Best-effort: a failure only means the dot lingers, so errors are swallowed
  /// rather than surfaced. Skipped offline — the read marker is low-value and
  /// not worth a queue slot.
  Future<void> markCommentsRead(
    ReadingLogModel log, {
    required String uid,
  }) async {
    if (!ServiceStatusController.instance.current.canWriteToFirebase) return;
    try {
      await _logRef(log).update({
        'commentsViewedAt.$uid': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('markCommentsRead failed for ${log.id}: $e');
    }
  }

  /// Resolves the book titles for a log: explicit titles win; otherwise the
  /// union of the student's effective assigned books (deduped). Returns an
  /// EMPTY list when nothing resolves — a generic placeholder ('Reading') is
  /// never fabricated. Quick-log callers turn empty into
  /// [NoCurrentBookException] / the "Choose book" state.
  List<String> _resolveBookTitles(
    List<String>? explicit,
    StudentModel student,
    List<AllocationModel> allocations,
  ) {
    final cleaned =
        explicit?.map((t) => t.trim()).where((t) => t.isNotEmpty).toList() ??
            const <String>[];
    if (cleaned.isNotEmpty) return cleaned;

    // No explicit selection (the one-tap quick path): attribute the night to
    // every assigned book, deduped, rather than just the first (D3: union
    // behaviour kept). The log is flagged `quickLog` so teachers can see the
    // books were inferred, not parent-confirmed.
    final seen = <String>{};
    final titles = <String>[];
    for (final allocation in allocations) {
      for (final item
          in allocation.effectiveAssignmentItemsForStudent(student.id)) {
        final title = item.title.trim();
        if (title.isEmpty) continue;
        if (!seen.add(title.toLowerCase())) continue;
        titles.add(IsbnAssignmentService.sanitizeDisplayTitle(title));
      }
    }
    return titles;
  }

  /// Joins comment chips and free-text into the denormalized `parentComment`
  /// string (mirrors the wizard's original composition).
  String _composeComment(List<String> selections, String? freeText) {
    final chips = selections.join('. ');
    final notes = freeText?.trim() ?? '';
    if (chips.isNotEmpty && notes.isNotEmpty) return '$chips. $notes';
    return chips.isNotEmpty ? chips : notes;
  }

  /// Computes a display-only **preview** of `students/{id}.stats` after [log],
  /// for the success-screen celebration. Does NOT write to Firestore.
  ///
  /// The aggregateStudentStats Cloud Function is the single source of truth and
  /// reconciles the persisted stats within ~1s (the home StreamBuilder then
  /// updates). This is a lightweight mirror of the server's gentle-streak rule
  /// — it tolerates up to 2 missed nights — and is intentionally approximate;
  /// the server corrects any drift.
  Future<_StatsUpdate> _previewStatsAfterLog(ReadingLogModel log) async {
    try {
      final studentRef = _firestore
          .collection('schools')
          .doc(log.schoolId)
          .collection('students')
          .doc(log.studentId);

      final studentDoc = await studentRef.get();
      if (!studentDoc.exists) return const _StatsUpdate(null, false);

      final data = studentDoc.data() as Map<String, dynamic>;
      final stats = data['stats'] as Map<String, dynamic>? ?? {};

      final currentStreak = (stats['currentStreak'] ?? 0) as int;
      final longestStreak = (stats['longestStreak'] ?? 0) as int;
      final totalMinutesRead = (stats['totalMinutesRead'] ?? 0) as int;
      final totalBooksRead = (stats['totalBooksRead'] ?? 0) as int;
      final totalReadingDays = (stats['totalReadingDays'] ?? 0) as int;

      final lastReadingDate = stats['lastReadingDate'] != null
          ? (stats['lastReadingDate'] as Timestamp).toDate().toLocal()
          : null;

      int newStreak = 1;
      bool isNewDay = true;
      bool restDayApplied = false;

      if (lastReadingDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final lastDay = DateTime(
          lastReadingDate.year,
          lastReadingDate.month,
          lastReadingDate.day,
        );
        final daysSinceLast = today.difference(lastDay).inDays;

        if (daysSinceLast == 0) {
          newStreak = currentStreak;
          isNewDay = false; // Already logged today — don't double-count.
        } else if (daysSinceLast == 1) {
          newStreak = currentStreak + 1; // Consecutive night.
        } else if (daysSinceLast <= 3) {
          // 1–2 missed nights, bridged by rest-day tolerance (≤ 2 days).
          newStreak = currentStreak + 1;
          restDayApplied = true;
        }
        // More missed nights than the tolerance → fresh start (newStreak = 1).
      }

      final newTotalDays = isNewDay ? totalReadingDays + 1 : totalReadingDays;

      final previewStats = <String, dynamic>{
        'totalMinutesRead': totalMinutesRead + log.minutesRead,
        'totalBooksRead': totalBooksRead + log.bookTitles.length,
        'currentStreak': newStreak,
        'longestStreak': newStreak > longestStreak ? newStreak : longestStreak,
        'totalReadingDays': newTotalDays,
      };

      return _StatsUpdate(previewStats, restDayApplied);
    } catch (e) {
      debugPrint('Error previewing student stats: $e');
      return const _StatsUpdate(null, false);
    }
  }
}
