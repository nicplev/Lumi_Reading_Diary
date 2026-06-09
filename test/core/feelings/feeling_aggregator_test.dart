import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/feelings/feeling_aggregator.dart';
import 'package:lumi_reading_tracker/data/models/reading_log_model.dart';

/// Builds a minimal reading log on [date] with an optional [feeling].
ReadingLogModel _log(DateTime date, {ReadingFeeling? feeling}) {
  return ReadingLogModel(
    id: 'id-${date.microsecondsSinceEpoch}-${feeling?.name ?? 'none'}',
    studentId: 's1',
    parentId: 'p1',
    schoolId: 'sch1',
    classId: 'c1',
    date: date,
    minutesRead: 10,
    targetMinutes: 10,
    status: LogStatus.completed,
    bookTitles: const ['Book'],
    createdAt: date,
    childFeeling: feeling,
  );
}

void main() {
  // A fixed "now": Wednesday 11 June 2025. Week starts Mon 9 June.
  final now = DateTime(2025, 6, 11);
  final weekStart = DateTime(2025, 6, 9); // Monday

  group('aggregateFeelings - week', () {
    test('empty input → 7 null buckets, no feelings', () {
      final s = aggregateFeelings(const [], period: FeelingPeriod.week, now: now);
      expect(s.buckets.length, 7);
      expect(s.hasAnyFeeling, isFalse);
      expect(s.showGlance, isTrue);
      expect(s.buckets.every((b) => b.value == null), isTrue);
      expect(s.buckets.map((b) => b.label).toList(),
          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']);
    });

    test('single feeling lands in the right day with its scale value', () {
      // Tuesday = weekStart + 1.
      final s = aggregateFeelings(
        [_log(weekStart.add(const Duration(days: 1)), feeling: ReadingFeeling.good)],
        period: FeelingPeriod.week,
        now: now,
      );
      expect(s.hasAnyFeeling, isTrue);
      expect(s.buckets[1].value, 4.0); // good = 4
      expect(s.buckets[1].feelingCount, 1);
      expect(s.buckets[0].value, isNull);
    });

    test('log with NULL feeling → bucket has a log but null value (not zero)', () {
      final s = aggregateFeelings(
        [_log(weekStart)], // Monday, no feeling (quick log / widget)
        period: FeelingPeriod.week,
        now: now,
      );
      expect(s.hasAnyFeeling, isFalse);
      expect(s.buckets[0].logCount, 1);
      expect(s.buckets[0].feelingCount, 0);
      expect(s.buckets[0].value, isNull);
    });

    test('multiple logs same day are averaged', () {
      final s = aggregateFeelings(
        [
          _log(weekStart, feeling: ReadingFeeling.great), // 5
          _log(weekStart, feeling: ReadingFeeling.hard), // 1
        ],
        period: FeelingPeriod.week,
        now: now,
      );
      expect(s.buckets[0].value, 3.0); // (5 + 1) / 2
      expect(s.buckets[0].feelingCount, 2);
    });

    test('mixed null + non-null same day averages only the recorded ones', () {
      final s = aggregateFeelings(
        [
          _log(weekStart, feeling: ReadingFeeling.good), // 4
          _log(weekStart), // null
        ],
        period: FeelingPeriod.week,
        now: now,
      );
      expect(s.buckets[0].value, 4.0);
      expect(s.buckets[0].logCount, 2);
      expect(s.buckets[0].feelingCount, 1);
    });

    test('logs outside the current week are ignored', () {
      final s = aggregateFeelings(
        [
          _log(weekStart.subtract(const Duration(days: 1)),
              feeling: ReadingFeeling.great), // last Sunday
          _log(weekStart.add(const Duration(days: 7)),
              feeling: ReadingFeeling.great), // next Monday
        ],
        period: FeelingPeriod.week,
        now: now,
      );
      expect(s.hasAnyFeeling, isFalse);
    });
  });

  group('aggregateFeelings - month', () {
    test('collapses to weekly buckets and hides the glance row', () {
      final s = aggregateFeelings(
        [_log(DateTime(2025, 6, 3), feeling: ReadingFeeling.okay)], // 3
        period: FeelingPeriod.month,
        now: now,
      );
      expect(s.showGlance, isFalse);
      expect(s.buckets.length, inInclusiveRange(4, 6));
      // 3 June is in the first week bucket.
      expect(s.buckets.first.value, 3.0);
      expect(s.buckets.first.label, 'W1');
    });
  });

  group('aggregateFeelings - all', () {
    test('produces 12 trailing monthly buckets, glance hidden', () {
      final s = aggregateFeelings(
        [_log(DateTime(2025, 6, 5), feeling: ReadingFeeling.tricky)], // 2
        period: FeelingPeriod.all,
        now: now,
      );
      expect(s.buckets.length, 12);
      expect(s.showGlance, isFalse);
      expect(s.buckets.last.label, 'Jun'); // current month is last
      expect(s.buckets.last.value, 2.0);
    });

    test('all-null history → friendly empty state', () {
      final s = aggregateFeelings(
        [_log(DateTime(2025, 6, 5)), _log(DateTime(2025, 5, 5))],
        period: FeelingPeriod.all,
        now: now,
      );
      expect(s.hasAnyFeeling, isFalse);
    });
  });
}
