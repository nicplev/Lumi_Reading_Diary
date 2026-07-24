import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// School-local calendar math for the parent logging flow — the Dart port of
/// `functions/src/dateUtils.ts` (`localDateString` / `localDateUtcRange`),
/// so the day a session belongs to is decided the same way on both sides.
///
/// Everything works on 'YYYY-MM-DD' school-local date strings, the same
/// vocabulary as `readingLogs.occurredOn`, `stats.readingDates[]` and the
/// quick-slot document IDs.
class SchoolTime {
  SchoolTime._();

  /// Mirrors the server's DEFAULT_TIMEZONE (functions/src/access.ts).
  static const String defaultTimezone = 'Australia/Sydney';

  static bool _initialized = false;

  /// Loads the bundled tz database once. Cheap to call repeatedly; also safe
  /// alongside NotificationService's own initializeTimeZones() call.
  static void ensureInitialized() {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    _initialized = true;
  }

  /// Resolves an IANA name to a location, falling back to the server default
  /// and then UTC — never throws on bad school data.
  static tz.Location locationFor(String? timezone) {
    ensureInitialized();
    final name = (timezone == null || timezone.trim().isEmpty)
        ? defaultTimezone
        : timezone.trim();
    try {
      return tz.getLocation(name);
    } catch (_) {
      try {
        return tz.getLocation(defaultTimezone);
      } catch (_) {
        return tz.UTC;
      }
    }
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  /// Formats [instant] as 'YYYY-MM-DD' in the school's timezone.
  static String localDateString(DateTime instant, String? timezone) {
    final local = tz.TZDateTime.from(instant.toUtc(), locationFor(timezone));
    return '${local.year}-${_twoDigits(local.month)}-${_twoDigits(local.day)}';
  }

  /// Today's school-local date string.
  static String todayFor(String? timezone, {DateTime? now}) =>
      localDateString(now ?? DateTime.now(), timezone);

  /// Shifts a 'YYYY-MM-DD' string by [delta] calendar days (UTC math, so no
  /// DST wobble — same approach as the server's shiftDays).
  static String shiftDays(String dateStr, int delta) {
    final base = DateTime.parse('${dateStr}T12:00:00Z');
    final shifted = base.add(Duration(days: delta));
    return '${shifted.year}-${_twoDigits(shifted.month)}-'
        '${_twoDigits(shifted.day)}';
  }

  /// UTC instant range [startInclusive, endExclusive) covering one school-
  /// local calendar day — the query window for "today's sessions".
  /// DST-correct: the range is 23/24/25 hours as the day demands.
  static ({DateTime startInclusive, DateTime endExclusive}) utcRangeForLocalDay(
    String dateStr,
    String? timezone,
  ) {
    final location = locationFor(timezone);
    final parts = dateStr.split('-').map(int.parse).toList();
    final start = tz.TZDateTime(location, parts[0], parts[1], parts[2]);
    final next = shiftDays(dateStr, 1).split('-').map(int.parse).toList();
    final end = tz.TZDateTime(location, next[0], next[1], next[2]);
    return (
      startInclusive: start.toUtc(),
      endExclusive: end.toUtc(),
    );
  }

  /// The next school-local midnight strictly after [now] as a UTC instant —
  /// arm the Home rollover timer with this so the day flips without an app
  /// restart.
  static DateTime nextMidnight(String? timezone, {DateTime? now}) {
    final instant = now ?? DateTime.now();
    final today = localDateString(instant, timezone);
    final tomorrow = shiftDays(today, 1);
    return utcRangeForLocalDay(tomorrow, timezone).startInclusive;
  }

  /// True when the device's local calendar date differs from the school's —
  /// drives the "Saving as {date} (school time)" disclosure.
  static bool deviceDayDiffers(String? timezone, {DateTime? now}) {
    final instant = now ?? DateTime.now();
    final device = instant.toLocal();
    final deviceDay = '${device.year}-${_twoDigits(device.month)}-'
        '${_twoDigits(device.day)}';
    return deviceDay != localDateString(instant, timezone);
  }
}
