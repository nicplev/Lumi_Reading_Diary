import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

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
  }) async {
    if (!_isSupported || children.isEmpty) return;
    try {
      final raw = await HomeWidget.getWidgetData<String>(_pendingLogsKey);
      if (raw == null || raw.isEmpty || raw == '[]') return;

      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;

      final byId = {for (final child in children) child.id: child};
      final processed = <String>{};
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final studentId = entry['studentId'] as String?;
        // Dedupe per child — the widget already dedupes per day.
        if (studentId == null || !processed.add(studentId)) continue;
        final child = byId[studentId];
        if (child == null) continue;
        try {
          await ReadingLogService.instance.logReading(
            student: child,
            parent: parent,
            quickLog: true,
          );
        } catch (e) {
          debugPrint('[WidgetDataService] widget log drain failed for '
              '$studentId: $e');
        }
      }

      // Queue reconciled — clear it and the optimistic flags.
      await HomeWidget.saveWidgetData<String>(_pendingLogsKey, '[]');
      await HomeWidget.saveWidgetData<String>(_optimisticKey, '');
    } catch (e) {
      debugPrint('[WidgetDataService] drainPendingWidgetLogs failed: $e');
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
