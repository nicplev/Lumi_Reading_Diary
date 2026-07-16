import 'package:flutter_test/flutter_test.dart';
import 'package:lumi_reading_tracker/data/providers/service_status_provider.dart';

void main() {
  group('PendingSyncHealth', () {
    test('surfaces a recent retrying item on a healthy connection', () {
      final health = PendingSyncHealth(
        total: 1,
        needsAttentionCount: 0,
        oldestPendingAt: DateTime.now(),
      );

      expect(health.hasPending, isTrue);
      expect(health.shouldSurface, isTrue);
      expect(health.shouldEscalate, isFalse);
    });

    test('does not surface an empty queue', () {
      const health = PendingSyncHealth(
        total: 0,
        needsAttentionCount: 0,
        oldestPendingAt: null,
      );

      expect(health.hasPending, isFalse);
      expect(health.shouldSurface, isFalse);
      expect(health.shouldEscalate, isFalse);
    });

    test('escalates a parked item', () {
      final health = PendingSyncHealth(
        total: 1,
        needsAttentionCount: 1,
        oldestPendingAt: DateTime.now(),
      );

      expect(health.shouldSurface, isTrue);
      expect(health.shouldEscalate, isTrue);
    });
  });
}
