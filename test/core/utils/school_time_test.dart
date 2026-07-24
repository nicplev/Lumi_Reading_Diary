import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/core/utils/school_time.dart';

/// Dart port of the server's day-boundary math (functions/src/dateUtils.ts)
/// — these cases mirror functions/test/dateUtils.test.js so a divergence
/// between client and server bucketing shows up as a failing test on
/// whichever side drifted.
void main() {
  test('localDateString buckets a late-night UTC instant into the local day',
      () {
    final instant = DateTime.utc(2026, 6, 7, 12, 30);
    expect(SchoolTime.localDateString(instant, 'Pacific/Auckland'),
        '2026-06-08');
    expect(
        SchoolTime.localDateString(
            DateTime.utc(2026, 6, 7, 3, 30), 'America/Los_Angeles'),
        '2026-06-06');
    expect(SchoolTime.localDateString(instant, 'UTC'), '2026-06-07');
  });

  test('a 23:30 Sydney log belongs to tonight, not tomorrow', () {
    // 13:30 UTC on the 24th = 23:30 AEST on the 24th.
    final instant = DateTime.utc(2026, 7, 24, 13, 30);
    expect(SchoolTime.localDateString(instant, 'Australia/Sydney'),
        '2026-07-24');
  });

  test('invalid or empty timezone falls back to the server default, never '
      'throws', () {
    final instant = DateTime.utc(2026, 7, 23, 21, 0); // 07:00 AEST on the 24th
    expect(SchoolTime.localDateString(instant, 'Not/AZone'), '2026-07-24');
    expect(SchoolTime.localDateString(instant, null), '2026-07-24');
    expect(SchoolTime.localDateString(instant, ''), '2026-07-24');
  });

  test('shiftDays handles day, month, year and leap boundaries', () {
    expect(SchoolTime.shiftDays('2026-06-07', -1), '2026-06-06');
    expect(SchoolTime.shiftDays('2026-01-01', -1), '2025-12-31');
    expect(SchoolTime.shiftDays('2026-03-01', -1), '2026-02-28');
    expect(SchoolTime.shiftDays('2024-03-01', -1), '2024-02-29');
    expect(SchoolTime.shiftDays('2026-06-07', 1), '2026-06-08');
  });

  test('utcRangeForLocalDay maps a Melbourne local day to UTC (matches '
      'server localDateUtcRange)', () {
    final range =
        SchoolTime.utcRangeForLocalDay('2026-06-07', 'Australia/Melbourne');
    expect(range.startInclusive.toIso8601String(), '2026-06-06T14:00:00.000Z');
    expect(range.endExclusive.toIso8601String(), '2026-06-07T14:00:00.000Z');
  });

  test('utcRangeForLocalDay follows Melbourne DST start (23-hour day)', () {
    final range =
        SchoolTime.utcRangeForLocalDay('2026-10-04', 'Australia/Melbourne');
    expect(
      range.endExclusive.difference(range.startInclusive),
      const Duration(hours: 23),
    );
  });

  test('nextMidnight lands exactly on the next school-local day start', () {
    final now = DateTime.utc(2026, 7, 24, 10, 0); // 20:00 AEST on the 24th
    final next = SchoolTime.nextMidnight('Australia/Sydney', now: now);
    expect(next.isAfter(now), isTrue);
    expect(SchoolTime.localDateString(next, 'Australia/Sydney'), '2026-07-25');
    expect(
        SchoolTime.localDateString(
            next.subtract(const Duration(seconds: 1)), 'Australia/Sydney'),
        '2026-07-24');
  });

  test('todayFor with an injected clock is deterministic across zones', () {
    final instant = DateTime.utc(2026, 7, 24, 15, 0);
    // 01:00 AEST on the 25th…
    expect(SchoolTime.todayFor('Australia/Sydney', now: instant),
        '2026-07-25');
    // …but still 08:00 on the 24th in Los Angeles.
    expect(SchoolTime.todayFor('America/Los_Angeles', now: instant),
        '2026-07-24');
  });
}
