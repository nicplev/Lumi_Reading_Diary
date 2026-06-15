import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/services/service_status_controller.dart';
import '../data/models/allocation_model.dart';
import '../data/models/log_comment_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/student_model.dart';
import '../data/models/user_model.dart';
import 'firebase_service.dart';
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
      id: id ?? now.millisecondsSinceEpoch.toString(),
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
      comprehensionAudioPath: comprehensionAudioPath,
      comprehensionAudioDurationSec: comprehensionAudioDurationSec,
      // Always false at create time; flipped after the Storage upload lands.
      comprehensionAudioUploaded: false,
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
    String? id,
    String? comprehensionAudioPath,
    int? comprehensionAudioDurationSec,
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
  }) {
    final now = DateTime.now();
    final cleanedTitles = bookTitles
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final titles = cleanedTitles.isNotEmpty ? cleanedTitles : const ['Reading'];
    final trimmedNotes = notes?.trim();

    final log = ReadingLogModel(
      id: now.millisecondsSinceEpoch.toString(),
      studentId: student.id,
      parentId: teacher.id,
      schoolId: student.schoolId,
      classId: student.classId,
      date: date,
      minutesRead: minutesRead,
      targetMinutes: targetMinutes,
      status: LogStatus.completed,
      bookTitles: titles,
      notes: (trimmedNotes != null && trimmedNotes.isNotEmpty)
          ? trimmedNotes
          : null,
      createdAt: now,
      allocationId: allocationId,
      loggedByName: teacher.fullName,
      loggedByLabel: 'Logged by ${teacher.fullName}',
      loggedByRole: LoggedByRole.teacher,
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
  Future<ReadingLogResult> writeLog(
    ReadingLogModel log, {
    StudentModel? student,
  }) async {
    if (ServiceStatusController.instance.current.canWriteToFirebase) {
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

      final statsUpdate = await _previewStatsAfterLog(log);

      // Push fresh data to the home-screen widget immediately after the log.
      if (student != null) {
        WidgetDataService.instance.updateAfterLog(student: student, log: log);
      }

      return ReadingLogResult(
        log: log,
        updatedStats: statsUpdate.stats,
        restDayApplied: statsUpdate.restDayApplied,
      );
    }

    // Offline: persist locally and queue for sync.
    final offlineLog = log.copyWith(isOfflineCreated: true);
    await OfflineService.instance.saveReadingLogLocally(offlineLog);
    if (student != null) {
      WidgetDataService.instance
          .updateAfterLog(student: student, log: offlineLog);
    }
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

  /// Builds the canonical Storage path for a comprehension audio recording.
  /// Filename matches the log id so a teacher viewing the log can resolve
  /// the audio without an extra lookup.
  static String comprehensionAudioStoragePath({
    required String schoolId,
    required String logId,
  }) =>
      'schools/$schoolId/comprehension_audio/$logId.m4a';

  /// Uploads the comprehension recording from [localFilePath] to the Storage
  /// path on [log], then patches the log doc to set
  /// `comprehensionAudioUploaded: true`. The temp file is removed after a
  /// confirmed update (best-effort).
  ///
  /// Throws on Storage or Firestore failure — the caller is expected to
  /// queue the upload via [OfflineService.enqueueComprehensionAudioUpload]
  /// when this throws so retries happen with backoff.
  Future<void> uploadComprehensionAudio({
    required ReadingLogModel log,
    required String localFilePath,
  }) async {
    final storagePath = log.comprehensionAudioPath;
    if (storagePath == null) {
      throw StateError('Log has no comprehensionAudioPath set');
    }
    final file = File(localFilePath);
    if (!file.existsSync()) {
      throw const ComprehensionAudioMissingException();
    }

    await FirebaseStorage.instance.ref(storagePath).putFile(
          file,
          SettableMetadata(
            contentType: 'audio/mp4',
            customMetadata: {
              'uploadedAt': DateTime.now().toUtc().toIso8601String(),
              'durationSec': '${log.comprehensionAudioDurationSec ?? 0}',
              'schoolId': log.schoolId,
              'studentId': log.studentId,
            },
          ),
        );

    await _logRef(log).update({'comprehensionAudioUploaded': true});

    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Best-effort: the temp dir gets purged by the OS eventually.
    }
  }

  /// Live comment thread for a log, oldest message first. Powers the in-app
  /// conversation view for both parents and teachers.
  ///
  /// The `studentId` equality filter is required, not cosmetic: the comment
  /// security rule authorizes a parent's `list` only when the query is scoped
  /// to a `studentId` in their `linkedChildren` (teachers are allowed
  /// unconditionally). Without it the parent read is silently denied and the
  /// thread renders empty even though writes succeed. All comments on a log
  /// share the log's `studentId`, so this never narrows the result set.
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
  Future<void> addComment(
    ReadingLogModel log, {
    required String body,
    required CommentAuthorRole authorRole,
    required String authorId,
    required String authorName,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

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
      return;
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
