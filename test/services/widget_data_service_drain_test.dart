import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/services/widget_data_service.dart';

/// The full [WidgetDataService.drainPendingWidgetLogs] flow is iOS-gated
/// (it returns early on non-iOS hosts), so what's worth unit-testing is the
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
}
