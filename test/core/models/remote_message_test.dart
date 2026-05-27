import 'package:flutter_test/flutter_test.dart';

import 'package:lumi_reading_tracker/core/models/remote_message.dart';

void main() {
  group('RemoteMessage', () {
    final fetched = DateTime.utc(2026, 5, 27, 10);

    test('isVisible false when id is null', () {
      final empty = RemoteMessage.fromJson(
        {'version': 0, 'id': null, 'message': null},
        fetchedAt: fetched,
      );
      expect(empty.isVisible, isFalse);
    });

    test('isVisible true with id and message', () {
      final m = RemoteMessage.fromJson(
        {
          'version': 3,
          'id': 'fb-out',
          'message': 'Lumi is having trouble.',
          'severity': 'warn',
          'updatedAt': '2026-05-27T10:00:00Z',
          'dismissible': true,
        },
        fetchedAt: fetched,
      );
      expect(m.isVisible, isTrue);
      expect(m.severity, RemoteMessageSeverity.warn);
      expect(m.dismissalKey, '3_fb-out');
    });

    test('severity defaults to info for unknown strings', () {
      final m = RemoteMessage.fromJson(
        {
          'version': 1,
          'id': 'x',
          'message': 'hi',
          'severity': 'banana',
        },
        fetchedAt: fetched,
      );
      expect(m.severity, RemoteMessageSeverity.info);
    });

    test('dismissible defaults to true and can be opted-out', () {
      final defaultMsg = RemoteMessage.fromJson(
        {'version': 1, 'id': 'x', 'message': 'hi'},
        fetchedAt: fetched,
      );
      expect(defaultMsg.dismissible, isTrue);

      final nonDismissible = RemoteMessage.fromJson(
        {'version': 1, 'id': 'x', 'message': 'hi', 'dismissible': false},
        fetchedAt: fetched,
      );
      expect(nonDismissible.dismissible, isFalse);
    });

    test('round-trips through cache', () {
      final original = RemoteMessage.fromJson(
        {
          'version': 5,
          'id': 'pinned',
          'message': 'Saved here for cache.',
          'severity': 'critical',
          'updatedAt': '2026-05-27T09:00:00Z',
          'dismissible': false,
        },
        fetchedAt: fetched,
      );
      final restored =
          RemoteMessage.fromCache(Map<String, dynamic>.from(original.toJson()));
      expect(restored.version, original.version);
      expect(restored.id, original.id);
      expect(restored.severity, RemoteMessageSeverity.critical);
      expect(restored.dismissible, isFalse);
    });
  });
}
