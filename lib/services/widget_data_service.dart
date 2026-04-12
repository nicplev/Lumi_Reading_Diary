import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../data/models/student_model.dart';
import '../data/models/reading_log_model.dart';

const _appGroupId = 'group.com.lumi.lumiReadingTracker';
const _widgetDataKey = 'lumi_widget_data';
const _widgetName = 'LumiWidget';

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

  /// Call once at app startup (after Firebase init).
  static Future<void> initialize() async {
    if (!_isSupported) return;
    await HomeWidget.setAppGroupId(_appGroupId);
  }

  /// Replaces the full children list. Called from ParentHomeScreen after load.
  Future<void> updateFromChildren({
    required List<StudentModel> children,
    required String selectedChildId,
    required Map<String, ReadingLogModel?> todaysLogs,
  }) async {
    if (!_isSupported) return;
    _selectedChildId = selectedChildId;
    _cachedChildren = children.map((student) {
      final log = todaysLogs[student.id];
      return _ChildPayload.fromStudent(student, log);
    }).toList();
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

  static bool get _isSupported => !kIsWeb && Platform.isIOS;
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
