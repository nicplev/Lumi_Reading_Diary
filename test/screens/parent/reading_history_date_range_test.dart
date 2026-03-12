import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/screens/parent/reading_history_screen.dart';

void main() {
  group('ReadingHistoryDateRange', () {
    test('startOfWeek returns Monday at midnight', () {
      final sample = DateTime(2026, 3, 11, 18, 45); // Wednesday
      final start = ReadingHistoryDateRange.startOfWeek(sample);

      expect(start, DateTime(2026, 3, 9));
      expect(start.weekday, DateTime.monday);
      expect(start.hour, 0);
      expect(start.minute, 0);
    });

    test('month boundaries are first day midnight and next month', () {
      final sample = DateTime(2026, 3, 31, 23, 59);
      final monthStart = ReadingHistoryDateRange.startOfMonth(sample);
      final nextMonthStart = ReadingHistoryDateRange.startOfNextMonth(sample);

      expect(monthStart, DateTime(2026, 3, 1));
      expect(nextMonthStart, DateTime(2026, 4, 1));
    });

    test('formatDurationMinutes produces compact readable strings', () {
      expect(ReadingHistoryDateRange.formatDurationMinutes(15), '15m');
      expect(ReadingHistoryDateRange.formatDurationMinutes(60), '1h');
      expect(ReadingHistoryDateRange.formatDurationMinutes(95), '1h 35m');
    });
  });
}
