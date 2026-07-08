import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/widget_data_service.dart';

/// The current widget no longer drains this queue into Firestore. These tests
/// keep the legacy queue parser pinned so stale App Group data can still be
/// parsed and cleared safely without throwing.
///
/// The full [WidgetDataService.drainPendingWidgetLogs] flow is iOS-gated
/// (it returns early on non-iOS hosts), so what is worth unit-testing is the
/// pure queue-parsing slice extracted as
/// [WidgetDataService.parsePendingQueue]. These cases pin the dedup +
/// filter-by-known-child + malformed-input behaviour that the widget bridge
/// relies on (Rec 4).
void main() {
  group('WidgetDataService.parsePendingQueue', () {
    const validIds = {'s1', 's2', 's3'};

    test('null / empty / "[]" / blank → empty queue', () {
      expect(WidgetDataService.parsePendingQueue(null, validIds), isEmpty);
      expect(WidgetDataService.parsePendingQueue('', validIds), isEmpty);
      expect(WidgetDataService.parsePendingQueue('[]', validIds), isEmpty);
    });

    test('malformed JSON → empty queue (no throw)', () {
      expect(
        WidgetDataService.parsePendingQueue('not-json', validIds),
        isEmpty,
      );
      expect(
        WidgetDataService.parsePendingQueue('{"studentId":"s1"}', validIds),
        isEmpty,
        reason: 'top-level must be a List',
      );
    });

    test('single valid entry → one studentId', () {
      const raw = '[{"studentId":"s1","date":"2026-05-24"}]';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        ['s1'],
      );
    });

    test('multiple distinct valid entries preserve order', () {
      const raw = '['
          '{"studentId":"s2","date":"2026-05-24"},'
          '{"studentId":"s1","date":"2026-05-24"},'
          '{"studentId":"s3","date":"2026-05-24"}'
          ']';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        ['s2', 's1', 's3'],
      );
    });

    test('duplicate entries for same student dedupe to first occurrence', () {
      const raw = '['
          '{"studentId":"s1","date":"2026-05-23"},'
          '{"studentId":"s1","date":"2026-05-24"},'
          '{"studentId":"s2","date":"2026-05-24"}'
          ']';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        ['s1', 's2'],
      );
    });

    test('entries for unknown students are dropped', () {
      const raw = '['
          '{"studentId":"unknown","date":"2026-05-24"},'
          '{"studentId":"s1","date":"2026-05-24"}'
          ']';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        ['s1'],
        reason: 'only currently-linked children should be reconciled',
      );
    });

    test('entries missing studentId or wrong type are dropped', () {
      const raw = '['
          '{"date":"2026-05-24"},'
          '"plain-string-not-a-map",'
          '{"studentId":null,"date":"2026-05-24"},'
          '{"studentId":"s2"}'
          ']';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        ['s2'],
      );
    });

    test('no valid students at all → empty queue', () {
      const raw = '[{"studentId":"ghost1"},{"studentId":"ghost2"}]';
      expect(
        WidgetDataService.parsePendingQueue(raw, validIds),
        isEmpty,
      );
    });
  });

  group('WidgetDataService.parsePendingQueueEntries', () {
    const validIds = {'s1', 's2', 's3'};

    test('preserves distinct dates for the same student', () {
      const raw = '['
          '{"studentId":"s1","date":"2026-05-23"},'
          '{"studentId":"s1","date":"2026-05-24"}'
          ']';

      final entries = WidgetDataService.parsePendingQueueEntries(raw, validIds);

      expect(entries.map((entry) => entry.studentId), ['s1', 's1']);
      expect(entries.map((entry) => entry.dateKey), [
        '2026-05-23',
        '2026-05-24',
      ]);
      expect(entries.first.readingDate, DateTime(2026, 5, 23));
      expect(entries.last.readingDate, DateTime(2026, 5, 24));
    });

    test('dedupes duplicate entries for the same student and date', () {
      const raw = '['
          '{"studentId":"s1","date":"2026-05-24"},'
          '{"studentId":"s1","date":"2026-05-24"},'
          '{"studentId":"s2","date":"2026-05-24"}'
          ']';

      final entries = WidgetDataService.parsePendingQueueEntries(raw, validIds);

      expect(entries.map((entry) => '${entry.studentId}:${entry.dateKey}'), [
        's1:2026-05-24',
        's2:2026-05-24',
      ]);
    });

    test('uses fallback date for missing or invalid date values', () {
      const raw = '['
          '{"studentId":"s1"},'
          '{"studentId":"s2","date":"2026-02-30"}'
          ']';

      final entries = WidgetDataService.parsePendingQueueEntries(
        raw,
        validIds,
        fallbackDate: DateTime(2026, 5, 30, 14, 45),
      );

      expect(entries.map((entry) => entry.dateKey), [
        '2026-05-30',
        '2026-05-30',
      ]);
      expect(entries.map((entry) => entry.readingDate), [
        DateTime(2026, 5, 30),
        DateTime(2026, 5, 30),
      ]);
    });
  });
}
