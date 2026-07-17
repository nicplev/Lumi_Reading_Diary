import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/class_model.dart';
import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';
import '../data/models/user_model.dart';
import 'class_daily_reading_service.dart';

const _appGroupId = 'group.com.lumi.lumiReadingTracker';
const _widgetDataKey = 'lumi_widget_data';
const _allWidgetNames = [
  'LumiWidget',
  'LumiTeacherTodayWidget',
  'LumiTeacherTopReadersWidget',
  'LumiTeacherCalendarWidget',
];
// Legacy App Group keys from the removed iOS live AppIntent logging flow.
// Current widget taps only deep-link into the app, but these are still cleared
// so stale pre-change queue state cannot create confusing optimistic UI.
const _pendingLogsKey = 'lumi_pending_widget_logs';
const _optimisticKey = 'lumi_optimistic_logged_ids';
const _undoUntilKey = 'lumi_widget_undo_until';
// Legacy in-app undo banner storage for logs committed by older widget builds.
// No new records are created now that widget taps only deep-link into the app.
const _recentCommitsPrefsKey = 'lumi_recent_widget_commits';
const _recentCommitsWindow = Duration(minutes: 5);
const _teacherCalendarDays = 42;

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
  _TeacherDashboardPayload? _cachedTeacherDashboard;

  // Rec 4: cached references for the lifecycle-driven drain. Populated on
  // `updateFromChildren`; needed because the WidgetsBindingObserver runs at
  // the app level and otherwise has no UserModel/StudentModel in scope.
  List<StudentModel> _cachedChildModels = const [];
  UserModel? _cachedParent;
  _LifecycleDrainObserver? _observer;

  // Coalesces concurrent legacy-queue clear callers onto a single future.
  Future<void>? _inFlightDrain;

  /// Call once at app startup (after Firebase init).
  static Future<void> initialize() async {
    if (!_isSupported) return;
    await HomeWidget.setAppGroupId(_appGroupId);
    await instance._clearLegacyLiveInteractionState();
    // Register a lifecycle observer so legacy widget queue state is cleared on
    // every app resume, not only while ParentHomeScreen is the active route. The
    // observer no-ops until updateFromChildren has cached the children + parent.
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
    _cachedTeacherDashboard = null;
    _cachedChildModels = const [];
    _cachedParent = null;
    _inFlightDrain = null;

    // Legacy in-app undo banner (SharedPreferences, not App Group) — runs on
    // every platform, so clear it regardless of [_isSupported].
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
        'accountRole': 'none',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedChildId': '',
        'children': <Map<String, dynamic>>[],
        'teacherDashboard': null,
      });
      await HomeWidget.saveWidgetData<String>(_widgetDataKey, emptyPayload);
      await HomeWidget.saveWidgetData<String>(_pendingLogsKey, '[]');
      await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
      await HomeWidget.saveWidgetData<String>(_undoUntilKey, '');
      await _reloadWidgets();
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
    _cachedTeacherDashboard = null;
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

  /// Replaces the full teacher dashboard payload used by the teacher-only iOS
  /// widgets. The caller must pass data already scoped to the signed-in
  /// teacher's selected class; the payload is display-only and contains no
  /// credentials or write-capable tokens.
  Future<void> updateFromTeacherDashboard({
    required UserModel teacher,
    required ClassModel classModel,
    required List<StudentModel> students,
    required List<ReadingLogModel> recentLogs,
    List<ClassDailyReadingSummary> dailySummaries = const [],
  }) async {
    if (!_isSupported || teacher.role != UserRole.teacher) return;
    _cachedChildren = [];
    _selectedChildId = '';
    _cachedChildModels = const [];
    _cachedParent = null;
    _cachedTeacherDashboard = _TeacherDashboardPayload.fromDashboard(
      teacher: teacher,
      classModel: classModel,
      students: students,
      recentLogs: recentLogs,
      dailySummaries: dailySummaries,
    );
    await _pushTeacherDashboard();
  }

  /// Keeps the teacher widget fresh after a teacher proxy-log is saved, without
  /// overwriting the teacher payload with the parent one-child widget payload.
  Future<void> updateAfterTeacherLog({
    required StudentModel student,
    required ReadingLogModel log,
  }) async {
    if (!_isSupported) return;
    final cached = _cachedTeacherDashboard;
    if (cached == null || cached.classId != student.classId) return;
    _cachedTeacherDashboard = cached.withAddedLog(student: student, log: log);
    await _pushTeacherDashboard();
  }

  /// Clears one-tap logs queued by older iOS widget builds.
  ///
  /// Current widget taps deep-link into the normal app logging flow instead of
  /// writing from the widget extension. This compatibility method intentionally
  /// does not create reading logs; it only removes stale App Group queue keys so
  /// a pre-change widget tap cannot be committed after an upgrade.
  Future<void> drainPendingWidgetLogs({
    required List<StudentModel> children,
    required UserModel parent,
  }) {
    return _inFlightDrain ??=
        _drainPendingWidgetLogsImpl().whenComplete(() => _inFlightDrain = null);
  }

  Future<void> _drainPendingWidgetLogsImpl() async {
    if (!_isSupported) return;
    try {
      await _clearLegacyLiveInteractionState();
    } catch (e) {
      debugPrint('[WidgetDataService] drainPendingWidgetLogs failed: $e');
    }
  }

  // ─── Legacy in-app widget undo banner ───────────────────────────────

  /// Fires whenever the recent-commits list changes (new commit recorded,
  /// undone, dismissed, or expired). UI watchers (the parent home banner)
  /// listen to this to refresh themselves without polling.
  final StreamController<void> _commitsChanges =
      StreamController<void>.broadcast();
  Stream<void> get recentCommitsChanges => _commitsChanges.stream;

  /// Legacy widget-originated reading logs still within the in-app undo window
  /// (~5 minutes). Excludes ones the parent already dismissed.
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
    await _reloadWidgets();
  }

  /// Removes the commit from the recent list without touching Firestore.
  /// Use for the "X" / "Got it" action on the banner.
  Future<void> dismissCommit(WidgetCommitRecord commit) async {
    await _removeCommit(commit);
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

  /// Pure parsing/dedupe of the legacy App Group pending-log queue.
  ///
  /// Exposed for testing (the surrounding [drainPendingWidgetLogs] is gated
  /// to iOS via `Platform.isIOS` and uses the `home_widget` plugin, so this
  /// is the slice that can be unit-tested on the host).
  ///
  /// - Returns the ordered list of unique student IDs represented in legacy
  ///   queue data.
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
    final processed = <String>{};
    final result = <String>[];
    for (final entry in parsePendingQueueEntries(raw, validStudentIds)) {
      if (!processed.add(entry.studentId)) continue;
      result.add(entry.studentId);
    }
    return result;
  }

  /// Parses legacy widget queue entries while preserving the captured date.
  ///
  /// The older [parsePendingQueue] intentionally returns only student IDs for
  /// compatibility with existing tests/callers. The drain uses this date-aware
  /// variant so a tap queued before midnight is committed to the intended
  /// reading day when the app next foregrounds.
  @visibleForTesting
  static List<WidgetPendingLog> parsePendingQueueEntries(
    String? raw,
    Set<String> validStudentIds, {
    DateTime? fallbackDate,
  }) {
    if (raw == null || raw.isEmpty || raw == '[]') return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return const [];
      final fallback = _dateOnly(fallbackDate ?? DateTime.now());
      final processed = <String>{};
      final result = <WidgetPendingLog>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final studentId = entry['studentId'];
        if (studentId is! String || studentId.isEmpty) continue;
        if (!validStudentIds.contains(studentId)) continue;
        final readingDate =
            _parseQueueDate(entry['date'] as String?) ?? fallback;
        final dateKey = _formatQueueDate(readingDate);
        if (!processed.add('$studentId|$dateKey')) continue;
        result.add(WidgetPendingLog(
          studentId: studentId,
          dateKey: dateKey,
          readingDate: readingDate,
        ));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static DateTime? _parseQueueDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    if (year == null || month == null || day == null) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String _formatQueueDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(_dateOnly(date));
  }

  Future<void> _clearLegacyLiveInteractionState() async {
    await HomeWidget.saveWidgetData<String>(_pendingLogsKey, '[]');
    await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
    await HomeWidget.saveWidgetData<String>(_undoUntilKey, '');
  }

  Future<void> _reloadWidgets() async {
    for (final widgetName in _allWidgetNames) {
      await HomeWidget.updateWidget(
        iOSName: widgetName,
        androidName: widgetName,
      );
    }
  }

  Future<void> _push() async {
    try {
      final payload = {
        'schemaVersion': 1,
        'accountRole': 'parent',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedChildId': _selectedChildId,
        'children': _cachedChildren.map((c) => c.toJson()).toList(),
        'teacherDashboard': null,
      };
      await HomeWidget.saveWidgetData<String>(
          _widgetDataKey, jsonEncode(payload));
      await _clearLegacyLiveInteractionState();
      await _reloadWidgets();
    } catch (e) {
      debugPrint('[WidgetDataService] Failed to push widget data: $e');
    }
  }

  Future<void> _pushTeacherDashboard() async {
    try {
      final payload = {
        'schemaVersion': 2,
        'accountRole': 'teacher',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'selectedChildId': '',
        'children': <Map<String, dynamic>>[],
        'teacherDashboard': _cachedTeacherDashboard?.toJson(),
      };
      await HomeWidget.saveWidgetData<String>(
          _widgetDataKey, jsonEncode(payload));
      await _clearLegacyLiveInteractionState();
      await _reloadWidgets();
    } catch (e) {
      debugPrint('[WidgetDataService] Failed to push teacher widget data: $e');
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

class WidgetPendingLog {
  const WidgetPendingLog({
    required this.studentId,
    required this.dateKey,
    required this.readingDate,
  });

  final String studentId;
  final String dateKey;
  final DateTime readingDate;

  Map<String, dynamic> toQueueJson() => {
        'studentId': studentId,
        'date': dateKey,
      };
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

  factory _ChildPayload.fromStudent(
      StudentModel student, ReadingLogModel? log) {
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
      if (last.year == now.year &&
          last.month == now.month &&
          last.day == now.day) {
        loggedToday = true;
        // Exact minutes not available without the log; widget shows ✓ state.
      }
    }

    return _ChildPayload(
      studentId: student.id,
      firstName: student.firstName,
      // NB: keeps the chosen profile character (not displayCharacterId). If a
      // child has not chosen one, the native widget falls back to red Lumi.
      characterId: student.characterId ?? 'lumi_red_default',
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

class _TeacherDashboardPayload {
  final String teacherId;
  final String schoolId;
  final String classId;
  final String className;
  final int totalStudents;
  final int readTodayCount;
  final int sessionsTodayCount;
  final int teacherLoggedTodayCount;
  final int onStreakCount;
  final int totalMinutesToday;
  final String todayDate;
  final Set<String> todayStudentIds;
  final Set<String> teacherLoggedStudentIds;
  final List<_TeacherCalendarDayPayload> calendarDays;
  final List<_TeacherTopReaderPayload> topReaders;

  const _TeacherDashboardPayload({
    required this.teacherId,
    required this.schoolId,
    required this.classId,
    required this.className,
    required this.totalStudents,
    required this.readTodayCount,
    required this.sessionsTodayCount,
    required this.teacherLoggedTodayCount,
    required this.onStreakCount,
    required this.totalMinutesToday,
    required this.todayDate,
    required this.todayStudentIds,
    required this.teacherLoggedStudentIds,
    required this.calendarDays,
    required this.topReaders,
  });

  factory _TeacherDashboardPayload.fromDashboard({
    required UserModel teacher,
    required ClassModel classModel,
    required List<StudentModel> students,
    required List<ReadingLogModel> recentLogs,
    List<ClassDailyReadingSummary> dailySummaries = const [],
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final today = WidgetDataService._dateOnly(current);
    final startOfWeek = WidgetDataService._dateOnly(
        current.subtract(Duration(days: current.weekday - 1)));
    final calendarStart =
        today.subtract(const Duration(days: _teacherCalendarDays - 1));

    final summariesByDate = {
      for (final summary in dailySummaries) summary.localDate: summary,
    };
    final hasSummaries = summariesByDate.isNotEmpty;
    final logsForClass =
        recentLogs.where((log) => log.classId == classModel.id).toList();
    final todayLogs = logsForClass
        .where((log) => WidgetDataService._dateOnly(log.date) == today)
        .toList();
    final weeklyLogs = logsForClass
        .where((log) =>
            !WidgetDataService._dateOnly(log.date).isBefore(startOfWeek))
        .toList();

    final calendarDays = <_TeacherCalendarDayPayload>[
      for (var i = 0; i < _teacherCalendarDays; i++)
        _TeacherCalendarDayPayload(
          date: WidgetDataService._formatQueueDate(
            calendarStart.add(Duration(days: i)),
          ),
          readCount: hasSummaries
              ? summariesByDate[WidgetDataService._formatQueueDate(
                          calendarStart.add(Duration(days: i)))]
                      ?.activeStudentCount ??
                  0
              : logsForClass
                  .where((log) =>
                      WidgetDataService._dateOnly(log.date) ==
                      calendarStart.add(Duration(days: i)))
                  .map((log) => log.studentId)
                  .toSet()
                  .length,
        ),
    ];

    final studentById = {for (final student in students) student.id: student};
    final minutesByStudent = <String, int>{};
    if (hasSummaries) {
      for (final summary in dailySummaries) {
        if (summary.date.isBefore(startOfWeek) || summary.date.isAfter(today)) {
          continue;
        }
        for (final entry in summary.students.entries) {
          minutesByStudent.update(
            entry.key,
            (minutes) => minutes + entry.value.minutes,
            ifAbsent: () => entry.value.minutes,
          );
        }
      }
    } else {
      for (final log in weeklyLogs) {
        minutesByStudent.update(
          log.studentId,
          (minutes) => minutes + log.minutesRead,
          ifAbsent: () => log.minutesRead,
        );
      }
    }
    final sortedReaders = minutesByStudent.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topReaders = <_TeacherTopReaderPayload>[];
    for (final entry in sortedReaders.take(3)) {
      final student = studentById[entry.key];
      if (student == null) continue;
      topReaders.add(_TeacherTopReaderPayload(
        studentId: student.id,
        firstName: student.firstName,
        characterId: student.characterId ?? 'lumi_red_default',
        minutes: entry.value,
      ));
    }

    var onStreakCount = 0;
    final yesterday = today.subtract(const Duration(days: 1));
    for (final student in students) {
      final stats = student.stats;
      if (stats == null || stats.currentStreak <= 0) continue;
      final lastRead = stats.lastReadingDate;
      if (lastRead == null) continue;
      final lastDay = WidgetDataService._dateOnly(lastRead);
      if (lastDay == today || lastDay == yesterday) onStreakCount++;
    }

    final todaySummary =
        summariesByDate[WidgetDataService._formatQueueDate(today)];
    final todayStudentIds = hasSummaries
        ? todaySummary?.students.keys.toSet() ?? <String>{}
        : todayLogs.map((log) => log.studentId).toSet();
    final teacherLoggedStudentIds = hasSummaries
        ? todaySummary?.students.entries
                .where((entry) => entry.value.teacherLogs > 0)
                .map((entry) => entry.key)
                .toSet() ??
            <String>{}
        : todayLogs
            .where((log) => log.isTeacherProxy)
            .map((log) => log.studentId)
            .toSet();

    return _TeacherDashboardPayload(
      teacherId: teacher.id,
      schoolId: teacher.schoolId ?? classModel.schoolId,
      classId: classModel.id,
      className: classModel.name,
      totalStudents: classModel.studentIds.length,
      readTodayCount: todayStudentIds.length,
      sessionsTodayCount:
          hasSummaries ? todaySummary?.logCount ?? 0 : todayLogs.length,
      teacherLoggedTodayCount: teacherLoggedStudentIds.length,
      onStreakCount: onStreakCount,
      totalMinutesToday: hasSummaries
          ? todaySummary?.totalMinutes ?? 0
          : todayLogs.fold<int>(0, (total, log) => total + log.minutesRead),
      todayDate: WidgetDataService._formatQueueDate(today),
      todayStudentIds: todayStudentIds,
      teacherLoggedStudentIds: teacherLoggedStudentIds,
      calendarDays: calendarDays,
      topReaders: topReaders,
    );
  }

  _TeacherDashboardPayload withAddedLog({
    required StudentModel student,
    required ReadingLogModel log,
  }) {
    final today = WidgetDataService._dateOnly(DateTime.now());
    if (WidgetDataService._dateOnly(log.date) != today) return this;
    final alreadyReadToday = todayStudentIds.contains(student.id);
    final alreadyTeacherLoggedToday =
        teacherLoggedStudentIds.contains(student.id);
    final updatedTodayStudentIds = {...todayStudentIds, student.id};
    final updatedTeacherLoggedStudentIds = log.isTeacherProxy
        ? {...teacherLoggedStudentIds, student.id}
        : teacherLoggedStudentIds;
    final updatedReadTodayCount =
        alreadyReadToday ? readTodayCount : readTodayCount + 1;
    final updatedTeacherLoggedTodayCount =
        log.isTeacherProxy && !alreadyTeacherLoggedToday
            ? teacherLoggedTodayCount + 1
            : teacherLoggedTodayCount;

    final updatedDays = [
      for (final day in calendarDays)
        if (day.date == WidgetDataService._formatQueueDate(today))
          day.copyWith(
            readCount: alreadyReadToday
                ? day.readCount
                : (day.readCount + 1 > totalStudents
                    ? totalStudents
                    : day.readCount + 1),
          )
        else
          day,
    ];

    final readersById = {
      for (final reader in topReaders) reader.studentId: reader,
    };
    final existingReader = readersById[student.id];
    readersById[student.id] = _TeacherTopReaderPayload(
      studentId: student.id,
      firstName: student.firstName,
      characterId: student.characterId ?? 'lumi_red_default',
      minutes: (existingReader?.minutes ?? 0) + log.minutesRead,
    );
    final updatedTopReaders = readersById.values.toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));

    return _TeacherDashboardPayload(
      teacherId: teacherId,
      schoolId: schoolId,
      classId: classId,
      className: className,
      totalStudents: totalStudents,
      readTodayCount: updatedReadTodayCount > totalStudents
          ? totalStudents
          : updatedReadTodayCount,
      sessionsTodayCount: sessionsTodayCount + 1,
      teacherLoggedTodayCount: updatedTeacherLoggedTodayCount,
      onStreakCount: onStreakCount,
      totalMinutesToday: totalMinutesToday + log.minutesRead,
      todayDate: todayDate,
      todayStudentIds: updatedTodayStudentIds,
      teacherLoggedStudentIds: updatedTeacherLoggedStudentIds,
      calendarDays: updatedDays,
      topReaders: updatedTopReaders.take(3).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'teacherId': teacherId,
        'schoolId': schoolId,
        'classId': classId,
        'className': className,
        'totalStudents': totalStudents,
        'readTodayCount': readTodayCount,
        'sessionsTodayCount': sessionsTodayCount,
        'teacherLoggedTodayCount': teacherLoggedTodayCount,
        'onStreakCount': onStreakCount,
        'totalMinutesToday': totalMinutesToday,
        'todayDate': todayDate,
        'calendarDays': calendarDays.map((day) => day.toJson()).toList(),
        'topReaders': topReaders.map((reader) => reader.toJson()).toList(),
      };
}

class _TeacherCalendarDayPayload {
  final String date;
  final int readCount;

  const _TeacherCalendarDayPayload({
    required this.date,
    required this.readCount,
  });

  _TeacherCalendarDayPayload copyWith({int? readCount}) =>
      _TeacherCalendarDayPayload(
        date: date,
        readCount: readCount ?? this.readCount,
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'readCount': readCount,
      };
}

class _TeacherTopReaderPayload {
  final String studentId;
  final String firstName;
  final String characterId;
  final int minutes;

  const _TeacherTopReaderPayload({
    required this.studentId,
    required this.firstName,
    required this.characterId,
    required this.minutes,
  });

  Map<String, dynamic> toJson() => {
        'studentId': studentId,
        'firstName': firstName,
        'characterId': characterId,
        'minutes': minutes,
      };
}

/// Legacy record for a reading log committed by older widget-tap drain builds,
/// retained in SharedPreferences while it's still within the in-app undo window.
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
