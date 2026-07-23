import '../../data/models/reading_log_model.dart';
import 'feeling_scale.dart';

/// The time window the feelings tracker is showing.
enum FeelingPeriod { week, month, all }

extension FeelingPeriodLabel on FeelingPeriod {
  String get label => switch (this) {
        FeelingPeriod.week => 'Week',
        FeelingPeriod.month => 'Month',
        FeelingPeriod.all => 'All time',
      };
}

/// One point on the x-axis of the feelings chart.
///
/// [value] is the feeling score (1.0–5.0) for the bucket, or `null` when no
/// feeling was recorded in this window — this covers BOTH "no reading log at
/// all" and "log(s) exist but `childFeeling` is null" (e.g. quick logs from the
/// home-screen widget or the parent dashboard). A null bucket is rendered as a
/// gap in the line and a neutral placeholder tile — never as zero.
///
/// The score is the LOWEST feeling of each day, averaged across the days in the
/// bucket (see [_bucketFromLogs]). For the week view a bucket is a single day,
/// so it is simply that day's lowest feeling — a hard session is surfaced rather
/// than averaged away behind a good one.
class FeelingBucket {
  /// Start of the bucket (a day for week view, week-start for month, month for
  /// all-time).
  final DateTime start;

  /// Short axis label (e.g. `Mon`, `W2`, `Apr`).
  final String label;

  /// Average feeling value (1.0–5.0), or null when nothing was recorded.
  final double? value;

  /// Number of reading logs in this bucket, regardless of feeling.
  final int logCount;

  /// Number of logs in this bucket that recorded a feeling.
  final int feelingCount;

  const FeelingBucket({
    required this.start,
    required this.label,
    required this.value,
    required this.logCount,
    required this.feelingCount,
  });

  bool get hasValue => value != null;
}

/// The aggregated series handed to the UI.
class FeelingSeries {
  final List<FeelingBucket> buckets;
  final FeelingPeriod period;

  /// True when at least one bucket has a recorded feeling. Drives the card-wide
  /// empty state.
  final bool hasAnyFeeling;

  /// True only for the week view — the per-day "at a glance" blob row is only
  /// legible at daily granularity, so it is hidden for month / all-time.
  final bool showGlance;

  const FeelingSeries({
    required this.buckets,
    required this.period,
    required this.hasAnyFeeling,
    required this.showGlance,
  });
}

const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Number of trailing months shown in the all-time view.
const _allTimeMonths = 12;

/// Buckets a student's [logs] into a [FeelingSeries] for the given [period].
///
/// Logs are bucketed by their reading [ReadingLogModel.date] (not `createdAt`),
/// so a back-dated offline log lands in the week it was actually read.
///
/// Within a day, the LOWEST feeling wins (so a struggle isn't hidden behind a
/// good session); across days in a coarser bucket those daily lows are averaged.
/// Logs without a feeling are excluded from the score but still counted in
/// [FeelingBucket.logCount].
///
/// [now] is injectable for deterministic tests.
FeelingSeries aggregateFeelings(
  List<ReadingLogModel> logs, {
  required FeelingPeriod period,
  DateTime? now,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  return switch (period) {
    FeelingPeriod.week => _aggregateWeek(logs, today),
    FeelingPeriod.month => _aggregateMonth(logs, today),
    FeelingPeriod.all => _aggregateAll(logs, today),
  };
}

FeelingSeries _aggregateWeek(List<ReadingLogModel> logs, DateTime today) {
  // Monday of the current week.
  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  final byDay = List.generate(7, (_) => <ReadingLogModel>[]);
  for (final log in logs) {
    final idx = _dateOnly(log.date).difference(weekStart).inDays;
    if (idx >= 0 && idx < 7) byDay[idx].add(log);
  }
  final buckets = [
    for (var i = 0; i < 7; i++)
      _bucketFromLogs(weekStart.add(Duration(days: i)), _dayLabels[i], byDay[i]),
  ];
  return _series(buckets, FeelingPeriod.week, showGlance: true);
}

FeelingSeries _aggregateMonth(List<ReadingLogModel> logs, DateTime today) {
  final monthStart = DateTime(today.year, today.month, 1);
  final nextMonth = DateTime(today.year, today.month + 1, 1);
  final daysInMonth = nextMonth.difference(monthStart).inDays;
  final weekCount = ((daysInMonth - 1) ~/ 7) + 1; // 4 or 5 weekly buckets
  final byWeek = List.generate(weekCount, (_) => <ReadingLogModel>[]);
  for (final log in logs) {
    final d = _dateOnly(log.date);
    if (d.isBefore(monthStart) || !d.isBefore(nextMonth)) continue;
    byWeek[(d.day - 1) ~/ 7].add(log);
  }
  final buckets = [
    for (var i = 0; i < weekCount; i++)
      _bucketFromLogs(
          monthStart.add(Duration(days: i * 7)), 'W${i + 1}', byWeek[i]),
  ];
  return _series(buckets, FeelingPeriod.month, showGlance: false);
}

FeelingSeries _aggregateAll(List<ReadingLogModel> logs, DateTime today) {
  final byMonth = <String, List<ReadingLogModel>>{};
  for (final log in logs) {
    final d = _dateOnly(log.date);
    byMonth.putIfAbsent('${d.year}-${d.month}', () => []).add(log);
  }
  final buckets = <FeelingBucket>[];
  for (var i = _allTimeMonths - 1; i >= 0; i--) {
    final m = DateTime(today.year, today.month - i, 1);
    buckets.add(_bucketFromLogs(
        m, _monthLabels[m.month - 1], byMonth['${m.year}-${m.month}'] ?? const []));
  }
  return _series(buckets, FeelingPeriod.all, showGlance: false);
}

FeelingBucket _bucketFromLogs(
  DateTime start,
  String label,
  List<ReadingLogModel> logs,
) {
  final feelings = logs.where((l) => l.childFeeling != null).toList();

  // Reduce each day to its lowest feeling, then average those daily lows. In the
  // week view a bucket is one day, so this is just that day's lowest feeling; in
  // month / all-time it prevents one hard day from defining the whole bucket.
  double? value;
  if (feelings.isNotEmpty) {
    final lowestByDay = <String, int>{};
    for (final l in feelings) {
      final d = _dateOnly(l.date);
      final key = '${d.year}-${d.month}-${d.day}';
      final v = l.childFeeling!.value;
      final existing = lowestByDay[key];
      if (existing == null || v < existing) lowestByDay[key] = v;
    }
    final lows = lowestByDay.values;
    value = lows.reduce((a, b) => a + b) / lows.length;
  }
  return FeelingBucket(
    start: start,
    label: label,
    value: value,
    logCount: logs.length,
    feelingCount: feelings.length,
  );
}

FeelingSeries _series(
  List<FeelingBucket> buckets,
  FeelingPeriod period, {
  required bool showGlance,
}) {
  return FeelingSeries(
    buckets: buckets,
    period: period,
    hasAnyFeeling: buckets.any((b) => b.hasValue),
    showGlance: showGlance,
  );
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
