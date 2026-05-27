import 'package:flutter_test/flutter_test.dart';

import 'package:lumi_reading_tracker/core/models/service_status.dart';

void main() {
  group('ServiceStatusSnapshot', () {
    ServiceStatusSnapshot snapshot(ServiceStatus status) {
      return ServiceStatusSnapshot(
        status: status,
        deviceConnected: status != ServiceStatus.offline,
        internetReachable:
            status == ServiceStatus.healthy ||
                status == ServiceStatus.degraded ||
                status == ServiceStatus.firebaseDown,
        firebaseReachable:
            status == ServiceStatus.healthy ||
                status == ServiceStatus.degraded,
        checkedAt: DateTime.utc(2026),
      );
    }

    test('canWriteToFirebase only true when healthy', () {
      expect(snapshot(ServiceStatus.healthy).canWriteToFirebase, isTrue);
      expect(snapshot(ServiceStatus.degraded).canWriteToFirebase, isFalse);
      expect(snapshot(ServiceStatus.firebaseDown).canWriteToFirebase, isFalse);
      expect(snapshot(ServiceStatus.offline).canWriteToFirebase, isFalse);
      expect(snapshot(ServiceStatus.unknown).canWriteToFirebase, isFalse);
    });

    test('shouldShowBanner suppresses healthy and unknown', () {
      expect(snapshot(ServiceStatus.healthy).shouldShowBanner, isFalse);
      expect(snapshot(ServiceStatus.unknown).shouldShowBanner, isFalse);
      expect(snapshot(ServiceStatus.degraded).shouldShowBanner, isTrue);
      expect(snapshot(ServiceStatus.firebaseDown).shouldShowBanner, isTrue);
      expect(snapshot(ServiceStatus.offline).shouldShowBanner, isTrue);
    });

    test('severity maps correctly', () {
      expect(snapshot(ServiceStatus.healthy).severity,
          ServiceStatusSeverity.none);
      expect(snapshot(ServiceStatus.unknown).severity,
          ServiceStatusSeverity.none);
      expect(snapshot(ServiceStatus.degraded).severity,
          ServiceStatusSeverity.info);
      expect(snapshot(ServiceStatus.firebaseDown).severity,
          ServiceStatusSeverity.warn);
      expect(snapshot(ServiceStatus.offline).severity,
          ServiceStatusSeverity.alert);
    });

    test('semanticallyEquals ignores latency', () {
      final a = ServiceStatusSnapshot(
        status: ServiceStatus.healthy,
        deviceConnected: true,
        internetReachable: true,
        firebaseReachable: true,
        lastProbeLatency: const Duration(milliseconds: 50),
        checkedAt: DateTime.utc(2026),
      );
      final b = a.copyWith(
        lastProbeLatency: const Duration(milliseconds: 500),
        checkedAt: DateTime.utc(2026, 1, 2),
      );
      expect(a.semanticallyEquals(b), isTrue);

      final c = a.copyWith(status: ServiceStatus.degraded);
      expect(a.semanticallyEquals(c), isFalse);
    });
  });
}
