import 'package:shared_preferences/shared_preferences.dart';

/// Tracks how engaged a parent is with the *detailed* logging flow, so we can
/// (a) surface an occasional, purpose-framed nudge toward it and (b) give gentle
/// positive recognition when they use it. All methods are best-effort and never
/// throw into the UI — encouragement should never break logging.
class LoggingEngagementService {
  LoggingEngagementService._();
  static final LoggingEngagementService instance =
      LoggingEngagementService._();

  static const _kDetailedCount = 'parent_detailed_log_count';
  static const _kLastDetailedAtMs = 'parent_last_detailed_log_at_ms';
  static const _kLastNudgeAtMs = 'parent_last_fullflow_nudge_at_ms';

  /// Don't nudge more often than this — the nudge must never feel like nagging.
  static const _nudgeCooldown = Duration(days: 3);

  /// "Been a while" since the parent last used the detailed flow.
  static const _staleAfter = Duration(days: 7);

  /// Records that a detailed (non-quick) log was completed. Returns the new
  /// running total so the success screen can recognise milestones.
  Future<int> recordDetailedLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = (prefs.getInt(_kDetailedCount) ?? 0) + 1;
      await prefs.setInt(_kDetailedCount, next);
      await prefs.setInt(
        _kLastDetailedAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      return next;
    } catch (_) {
      return 0;
    }
  }

  /// Total number of detailed logs this parent has completed.
  Future<int> detailedLogCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_kDetailedCount) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Whether to surface the occasional full-flow nudge right now. True only
  /// when we haven't nudged recently AND it's a good moment: a weekend (parents
  /// have more time), or it's been a while since the last detailed log.
  Future<bool> shouldShowFullFlowNudge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();

      final lastNudgeMs = prefs.getInt(_kLastNudgeAtMs) ?? 0;
      if (now.difference(DateTime.fromMillisecondsSinceEpoch(lastNudgeMs)) <
          _nudgeCooldown) {
        return false;
      }

      final isWeekend =
          now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

      final lastDetailedMs = prefs.getInt(_kLastDetailedAtMs);
      final beenAWhile = lastDetailedMs == null ||
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastDetailedMs)) >
              _staleAfter;

      return isWeekend || beenAWhile;
    } catch (_) {
      return false;
    }
  }

  /// Marks that the nudge was shown so the cooldown applies.
  Future<void> markNudgeShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _kLastNudgeAtMs,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }
}
