import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/user_model.dart';
import 'reading_log_service.dart';

const _appGroupId = 'group.com.lumi.lumiReadingTracker';
const _widgetDataKey = 'lumi_widget_data';
const _widgetName = 'LumiWidget';
// Rec 4: App Group keys shared with the iOS widget's LogReadingIntent.
const _pendingLogsKey = 'lumi_pending_widget_logs';
const _optimisticKey = 'lumi_optimistic_logged_ids';
// Layer 1 (widget undo): `studentId -> ISO8601` map of "post-tap undo window
// expires at" timestamps written by Swift's `WidgetLogQueue.enqueue`. While
// the timestamp is in the future the widget renders an "Undo" CTA and the
// drain below skips the entry so no Firestore write happens.
const _undoUntilKey = 'lumi_widget_undo_until';
// Layer 2 (in-app undo banner): JSON list of recently-committed widget logs
// stored in SharedPreferences so a parent who didn't catch the 10-second
// widget undo can still reverse the log from inside the app for ~5 minutes.
const _recentCommitsPrefsKey = 'lumi_recent_widget_commits';
const _recentCommitsWindow = Duration(minutes: 5);

/// Manages data written to the iOS home screen widget via App Group shared storage.
///
/// Call [updateFromChildren] whenever the parent's children list is loaded, and
/// [updateAfterLog] immediately after a reading log is saved.
class WidgetDataService {
  WidgetDataService._();
  static final WidgetDataService instance = WidgetDataService._();

  // In-memory cache of the latest payload so partial updates (single child)
  // can be merged without re-fetching all children.
  List<_ChildPayload> _cachedChildren = [];
  String _selectedChildId = '';

  // Rec 4: cached references for the lifecycle-driven drain. Populated on
  // `updateFromChildren`; needed because the WidgetsBindingObserver runs at
  // the app level and otherwise has no UserModel/StudentModel in scope.
  List<StudentModel> _cachedChildModels = const [];
  UserModel? _cachedParent;
  _LifecycleDrainObserver? _observer;

  // Coalesces concurrent drain callers onto a single future. On app resume
  // ParentHomeScreen's lifecycle observer AND its parentChildrenProvider
  // re-emit listener both fire `drainPendingWidgetLogs` within a few ms,
  // racing on the pending queue and writing the same tap twice to Firestore.
  Future<void>? _inFlightDrain;

  /// Call once at app startup (after Firebase init).
  static Future<void> initialize() async {
    if (!_isSupported) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    // Rec 4: register a lifecycle observer so the pending-widget-log queue
    // drains on every app resume, not only while ParentHomeScreen is the
    // active route. The observer no-ops until updateFromChildren has cached
    // the children + parent on a prior session.
    instance._observer ??= _LifecycleDrainObserver(instance);
    WidgetsBinding.instance.addObserver(instance._observer!);
  }

  /// Wipe every widget storage surface and reset the in-memory cache. Called
  /// from sign-out so the home-screen widget can't keep showing the previous
  /// account's child names, and the in-app undo banner can't try to delete a
  /// log out of the prior parent's school.
  ///
  /// App Group payload is replaced with an empty-children document (rather
  /// than nuked) so the iOS widget decodes cleanly and renders its
  /// placeholder; an empty/missing JSON would also fall through to the
  /// placeholder but via the decode-error path, which is noisier.
  Future<void> clearAll() async {
    _cachedChildren = [];
    _selectedChildId = '';
    _cachedChildModels = const [];
    _cachedParent = null;
    _inFlightDrain = null;

    // In-app undo banner (SharedPreferences, not App Group) — runs on every
    // platform, so clear it regardless of [_isSupported].
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentCommitsPrefsKey);
      if (!_commitsChanges.isClosed) _commitsChanges.add(null);
    } catch (e) {
      debugPrint('[WidgetDataService] clearAll: prefs remove failed: $e');
    }

    if (!_isSupported) return;

    try {
      final emptyPayload = jsonEncode({
        'schemaVersion': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedChildId': '',
        'children': <Map<String, dynamic>>[],
      });
      await HomeWidget.saveWidgetData<String>(_widgetDataKey, emptyPayload);
      await HomeWidget.saveWidgetData<String>(_pendingLogsKey, '[]');
      await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
      await HomeWidget.saveWidgetData<String>(_undoUntilKey, '');
      await HomeWidget.updateWidget(
        iOSName: _widgetName,
        androidName: _widgetName,
      );
    } catch (e) {
      debugPrint('[WidgetDataService] clearAll: widget wipe failed: $e');
    }
  }

  /// Replaces the full children list. Called from ParentHomeScreen after load.
  Future<void> updateFromChildren({
    required List<StudentModel> children,
    required String selectedChildId,
    required Map<String, ReadingLogModel?> todaysLogs,
    UserModel? parent,
  }) async {
    if (!_isSupported) return;
    _selectedChildId = selectedChildId;
    _cachedChildren = children.map((student) {
      final log = todaysLogs[student.id];
      return _ChildPayload.fromStudent(student, log);
    }).toList();
    _cachedChildModels = children;
    if (parent != null) _cachedParent = parent;
    await _push();
  }

  /// Updates a single child's logged state after a reading log is saved.
  Future<void> updateAfterLog({
    required StudentModel student,
    required ReadingLogModel log,
  }) async {
    if (!_isSupported) return;
    final updated = _ChildPayload.fromStudent(student, log);
    final idx = _cachedChildren.indexWhere((c) => c.studentId == student.id);
    if (idx >= 0) {
      _cachedChildren[idx] = updated;
    } else {
      _cachedChildren.add(updated);
      _selectedChildId = student.id;
    }
    await _push();
  }

  /// Reconciles one-tap logs queued by the iOS widget's `LogReadingIntent`.
  ///
  /// The widget extension can't reach Firestore, so each tap is queued in App
  /// Group storage; this drains that queue on app launch/resume and performs
  /// the real writes via [ReadingLogService]. Call when the parent's children
  /// are loaded (see ParentHomeScreen).
  Future<void> drainPendingWidgetLogs({
    required List<StudentModel> children,
    required UserModel parent,
  }) {
    return _inFlightDrain ??= _drainPendingWidgetLogsImpl(
      children: children,
      parent: parent,
    ).whenComplete(() => _inFlightDrain = null);
  }

  Future<void> _drainPendingWidgetLogsImpl({
    required List<StudentModel> children,
    required UserModel parent,
  }) async {
    if (!_isSupported || children.isEmpty) return;
    try {
      final raw = await HomeWidget.getWidgetData<String>(_pendingLogsKey);
      final validIds = {for (final child in children) child.id};
      final queuedIds = parsePendingQueue(raw, validIds);
      if (queuedIds.isEmpty) return;

      // Two-layer undo model:
      //   • Layer 1 (widget Undo button, 10 s) is for the home-screen flow:
      //     parent taps Log on the widget then realises mid-tap. The pending
      //     queue + undoUntil timestamp in App Group keep that recoverable
      //     until the app is opened.
      //   • Layer 2 (in-app banner, ~5 min) takes over the moment the app is
      //     foregrounded. Commit immediately, capture pre-write stats, and
      //     surface the banner — far less confusing than making the parent
      //     stare at the home screen waiting for a Timer to fire.
      // So we no longer skip entries whose widget undo window is still open.

      final byId = {for (final child in children) child.id: child};
      for (final studentId in queuedIds) {
        final child = byId[studentId]!;
        try {
          final result = await ReadingLogService.instance.logReading(
            student: child,
            parent: parent,
            quickLog: true,
          );
          await _recordWidgetCommit(
            studentId: studentId,
            firstName: child.firstName,
            logId: result.log.id,
            schoolId: child.schoolId,
            committedAt: DateTime.now(),
          );
        } catch (e) {
          debugPrint('[WidgetDataService] widget log drain failed for '
              '$studentId: $e');
        }
      }

      // Clear all transient widget-side state — the queue is now drained, the
      // optimistic flags served their purpose, and any open undo window is
      // moot now that the banner has taken over. Clearing undoUntil also
      // flips the widget's CTA back from "Undo" to "View today" on the next
      // refresh that `updateAfterLog` already kicked off inside writeLog.
      await HomeWidget.saveWidgetData<String>(_pendingLogsKey, '[]');
      await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
      await HomeWidget.saveWidgetData<String>(_undoUntilKey, '');
    } catch (e) {
      debugPrint('[WidgetDataService] drainPendingWidgetLogs failed: $e');
    }
  }

  // ─── Layer 2: in-app undo banner ────────────────────────────────────

  /// Fires whenever the recent-commits list changes (new commit recorded,
  /// undone, dismissed, or expired). UI watchers (the parent home banner)
  /// listen to this to refresh themselves without polling.
  final StreamController<void> _commitsChanges =
      StreamController<void>.broadcast();
  Stream<void> get recentCommitsChanges => _commitsChanges.stream;

  /// Recent widget-originated reading logs still within the in-app undo
  /// window (~5 minutes). Excludes ones the parent already dismissed.
  /// Newest first.
  Future<List<WidgetCommitRecord>> recentCommits() async {
    final all = await _loadCommits();
    final cutoff = DateTime.now().subtract(_recentCommitsWindow);
    final live = all.where((c) => c.committedAt.isAfter(cutoff)).toList();
    if (live.length != all.length) {
      await _saveCommits(live);
    }
    live.sort((a, b) => b.committedAt.compareTo(a.committedAt));
    return live;
  }

  /// Reverses a recent widget log by deleting the Firestore log doc.
  ///
  /// Stats are NOT touched client-side. The `aggregateStudentStats` Cloud
  /// Function ([functions/src/index.ts]) recomputes the student's stats from
  /// the remaining reading logs whenever a log doc is written or deleted, so
  /// the streak / minutes / freezes settle to their pre-log values within a
  /// second of the delete. Going through the function also keeps stats
  /// updates within the security boundary parents are allowed to cross.
  Future<void> undoCommit(WidgetCommitRecord commit) async {
    final logRef = FirebaseFirestore.instance
        .collection('schools')
        .doc(commit.schoolId)
        .collection('readingLogs')
        .doc(commit.logId);
    try {
      await logRef.delete();
    } catch (e) {
      debugPrint('[WidgetDataService] undoCommit failed: $e');
      rethrow;
    }
    await _removeCommit(commit);
    // Clear the optimistic flag for this child so the widget flips back to
    // its non-celebrating state immediately rather than waiting on the
    // next parentChildrenProvider re-emit.
    await _clearOptimisticForStudent(commit.studentId);
    await HomeWidget.updateWidget(
      iOSName: _widgetName,
      androidName: _widgetName,
    );
  }

  /// Removes the commit from the recent list without touching Firestore.
  /// Use for the "X" / "Got it" action on the banner.
  Future<void> dismissCommit(WidgetCommitRecord commit) async {
    await _removeCommit(commit);
  }

  Future<void> _recordWidgetCommit({
    required String studentId,
    required String firstName,
    required String logId,
    required String schoolId,
    required DateTime committedAt,
  }) async {
    final commits = await _loadCommits();
    commits.add(WidgetCommitRecord(
      studentId: studentId,
      firstName: firstName,
      logId: logId,
      schoolId: schoolId,
      committedAt: committedAt,
    ));
    await _saveCommits(commits);
  }

  Future<void> _removeCommit(WidgetCommitRecord commit) async {
    final commits = await _loadCommits();
    commits.removeWhere((c) => c.logId == commit.logId);
    await _saveCommits(commits);
  }

  Future<List<WidgetCommitRecord>> _loadCommits() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentCommitsPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final entry in decoded)
          if (entry is Map<String, dynamic>) WidgetCommitRecord.fromJson(entry),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCommits(List<WidgetCommitRecord> commits) async {
    final prefs = await SharedPreferences.getInstance();
    if (commits.isEmpty) {
      await prefs.remove(_recentCommitsPrefsKey);
    } else {
      await prefs.setString(
        _recentCommitsPrefsKey,
        jsonEncode(commits.map((c) => c.toJson()).toList()),
      );
    }
    if (!_commitsChanges.isClosed) _commitsChanges.add(null);
  }

  Future<void> _clearOptimisticForStudent(String studentId) async {
    // The optimistic-flags App Group entry is a JSON-ish blob `home_widget`
    // round-trips as a String. We don't read it from Dart elsewhere — easiest
    // is to clear the whole map; the next genuine log will repopulate.
    await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
  }

  /// Pure parsing/dedupe of the App Group pending-log queue.
  ///
  /// Exposed for testing (the surrounding [drainPendingWidgetLogs] is gated
  /// to iOS via `Platform.isIOS` and uses the `home_widget` plugin, so this
  /// is the slice that can be unit-tested on the host).
  ///
  /// - Returns the ordered list of unique student IDs that should be
  ///   reconciled to real reading logs.
  /// - Drops entries that aren't well-formed maps with a non-null
  ///   `studentId`, or that reference a student not in [validStudentIds].
  /// - Dedupes per student (the widget already dedupes per day, but a
  ///   defensive second pass keeps the drain idempotent if the App Group
  ///   storage somehow accumulates duplicates).
  /// - Treats null / empty / `'[]'` / malformed JSON as an empty queue.
  @visibleForTesting
  static List<String> parsePendingQueue(
    String? raw,
    Set<String> validStudentIds,
  ) {
    if (raw == null || raw.isEmpty || raw == '[]') return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return const [];
      final processed = <String>{};
      final result = <String>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final studentId = entry['studentId'] as String?;
        if (studentId == null) continue;
        if (!validStudentIds.contains(studentId)) continue;
        if (!processed.add(studentId)) continue;
        result.add(studentId);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _push() async {
    try {
      final payload = {
        'schemaVersion': 1,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedChildId': _selectedChildId,
        'children': _cachedChildren.map((c) => c.toJson()).toList(),
      };
      await HomeWidget.saveWidgetData<String>(_widgetDataKey, jsonEncode(payload));
      await HomeWidget.updateWidget(
        iOSName: _widgetName,
        androidName: _widgetName,
      );
    } catch (e) {
      debugPrint('[WidgetDataService] Failed to push widget data: $e');
    }
  }

  /// Re-runs the drain using the cached children + parent. Returns silently
  /// when no context is cached yet (first launch before ParentHomeScreen has
  /// reported its children) — the existing parent-home init drain will pick
  /// up that case.
  Future<void> drainWithCachedContext() async {
    final parent = _cachedParent;
    if (parent == null || _cachedChildModels.isEmpty) return;
    await drainPendingWidgetLogs(
      children: _cachedChildModels,
      parent: parent,
    );
  }

  static bool get _isSupported => !kIsWeb && Platform.isIOS;
}

class _LifecycleDrainObserver with WidgetsBindingObserver {
  _LifecycleDrainObserver(this._service);
  final WidgetDataService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Fire-and-forget — drain is best-effort and silently no-ops when
      // there's no cached context yet.
      _service.drainWithCachedContext();
    }
  }
}

class _ChildPayload {
  final String studentId;
  final String firstName;
  final String characterId;
  final int currentStreak;
  final String lastReadingDate;
  final int minutesReadToday;
  final int targetMinutes;
  final bool loggedToday;

  _ChildPayload({
    required this.studentId,
    required this.firstName,
    required this.characterId,
    required this.currentStreak,
    required this.lastReadingDate,
    required this.minutesReadToday,
    required this.targetMinutes,
    required this.loggedToday,
  });

  factory _ChildPayload.fromStudent(StudentModel student, ReadingLogModel? log) {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // Use block-level promotion so Dart's type system can track null safety cleanly.
    int minutesReadToday = 0;
    int targetMinutes = 20;
    bool loggedToday = false;

    if (log != null &&
        log.date.year == now.year &&
        log.date.month == now.month &&
        log.date.day == now.day) {
      // Explicit log passed in — use it directly.
      minutesReadToday = log.minutesRead;
      targetMinutes = log.targetMinutes;
      loggedToday = true;
    } else if (student.stats?.lastReadingDate != null) {
      // Fallback: infer from stats so the widget shows the correct state when
      // the app is opened after a log was already saved in a prior session.
      final last = student.stats!.lastReadingDate!;
      if (last.year == now.year && last.month == now.month && last.day == now.day) {
        loggedToday = true;
        // Exact minutes not available without the log; widget shows ✓ state.
      }
    }

    return _ChildPayload(
      studentId: student.id,
      firstName: student.firstName,
      // NB: keeps the chosen character (not displayCharacterId) — the native
      // home-screen widget bundles its own character assets and has no
      // gold/special award art, so an award id would render blank there.
      characterId: student.characterId ?? 'character_default',
      currentStreak: student.stats?.currentStreak ?? 0,
      lastReadingDate: student.stats?.lastReadingDate != null
          ? DateFormat('yyyy-MM-dd').format(student.stats!.lastReadingDate!)
          : todayStr,
      minutesReadToday: minutesReadToday,
      targetMinutes: targetMinutes,
      loggedToday: loggedToday,
    );
  }

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'firstName': firstName,
        'characterId': characterId,
        'currentStreak': currentStreak,
        'lastReadingDate': lastReadingDate,
        'minutesReadToday': minutesReadToday,
        'targetMinutes': targetMinutes,
        'loggedToday': loggedToday,
      };
}

/// A reading log committed to Firestore via the widget-tap drain, retained in
/// SharedPreferences while it's still within the in-app undo window.
///
/// Stats restore is handled server-side by the `aggregateStudentStats` Cloud
/// Function on log delete, so the record only needs the identifiers needed to
/// locate the log doc and present a friendly banner.
class WidgetCommitRecord {
  final String studentId;
  final String firstName;
  final String logId;
  final String schoolId;
  final DateTime committedAt;

  const WidgetCommitRecord({
    required this.studentId,
    required this.firstName,
    required this.logId,
    required this.schoolId,
    required this.committedAt,
  });

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'firstName': firstName,
        'logId': logId,
        'schoolId': schoolId,
        'committedAt': committedAt.toIso8601String(),
      };

  factory WidgetCommitRecord.fromJson(Map<String, dynamic> json) =>
      WidgetCommitRecord(
        studentId: json['studentId'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        logId: json['logId'] as String? ?? '',
        schoolId: json['schoolId'] as String? ?? '',
        committedAt: DateTime.tryParse(json['committedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
