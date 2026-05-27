import 'package:flutter/foundation.dart';

/// High-level health of Lumi's network-dependent services as seen from this
/// device. Driven by [ServiceStatusController]'s layered probe (device
/// connectivity → public-internet HEAD → Firestore healthcheck read).
enum ServiceStatus {
  /// Initial state before the first probe completes. Suppresses the global
  /// banner so we don't flash a warning during the ~1s startup probe.
  unknown,

  /// All three layers green and L3 latency is within budget.
  healthy,

  /// Internet is fine and Firestore is reachable, but L3 latency exceeded
  /// the budget. Writes still go through but the UI nudges the user.
  degraded,

  /// Internet is fine but Firestore is unreachable or erroring. Treated as
  /// "queue writes locally" — same as offline for write decisions.
  firebaseDown,

  /// Device has no connectivity, or a captive-portal / DNS-broken network
  /// where the public-internet HEAD failed.
  offline,
}

/// Snapshot of the per-layer probe results plus a derived [ServiceStatus].
///
/// Consumers should generally prefer the computed helpers
/// ([canWriteToFirebase], [shouldShowBanner], [severity]) over branching on
/// the raw enum so future status additions (e.g. `degradedAuth`) don't
/// require touching every call site.
@immutable
class ServiceStatusSnapshot {
  const ServiceStatusSnapshot({
    required this.status,
    required this.deviceConnected,
    required this.internetReachable,
    required this.firebaseReachable,
    required this.checkedAt,
    this.lastProbeLatency,
  });

  factory ServiceStatusSnapshot.unknown() => ServiceStatusSnapshot(
        status: ServiceStatus.unknown,
        deviceConnected: false,
        internetReachable: false,
        firebaseReachable: false,
        checkedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  final ServiceStatus status;
  final bool deviceConnected;
  final bool internetReachable;
  final bool firebaseReachable;
  final Duration? lastProbeLatency;
  final DateTime checkedAt;

  /// True iff writes to Firestore are likely to succeed without queuing.
  /// Callers (e.g. `ReadingLogService.writeLog`) gate the online branch on
  /// this. `degraded` is intentionally false — better to queue than gamble
  /// on a transaction stalling for tens of seconds.
  bool get canWriteToFirebase => status == ServiceStatus.healthy;

  /// True iff the global banner should be visible. `unknown` returns false
  /// to suppress the bootstrap flicker.
  bool get shouldShowBanner =>
      status != ServiceStatus.healthy && status != ServiceStatus.unknown;

  ServiceStatusSeverity get severity {
    switch (status) {
      case ServiceStatus.unknown:
      case ServiceStatus.healthy:
        return ServiceStatusSeverity.none;
      case ServiceStatus.degraded:
        return ServiceStatusSeverity.info;
      case ServiceStatus.firebaseDown:
        return ServiceStatusSeverity.warn;
      case ServiceStatus.offline:
        return ServiceStatusSeverity.alert;
    }
  }

  /// Whether the snapshot's *observable* fields are equal. Latency-only
  /// changes are intentionally ignored so the stream doesn't emit on every
  /// 30s probe.
  bool semanticallyEquals(ServiceStatusSnapshot other) {
    return status == other.status &&
        deviceConnected == other.deviceConnected &&
        internetReachable == other.internetReachable &&
        firebaseReachable == other.firebaseReachable;
  }

  ServiceStatusSnapshot copyWith({
    ServiceStatus? status,
    bool? deviceConnected,
    bool? internetReachable,
    bool? firebaseReachable,
    Duration? lastProbeLatency,
    DateTime? checkedAt,
  }) {
    return ServiceStatusSnapshot(
      status: status ?? this.status,
      deviceConnected: deviceConnected ?? this.deviceConnected,
      internetReachable: internetReachable ?? this.internetReachable,
      firebaseReachable: firebaseReachable ?? this.firebaseReachable,
      lastProbeLatency: lastProbeLatency ?? this.lastProbeLatency,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }
}

enum ServiceStatusSeverity { none, info, warn, alert }
