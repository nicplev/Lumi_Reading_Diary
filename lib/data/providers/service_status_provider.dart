import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/service_status.dart';
import '../../core/services/service_status_controller.dart';
import '../../services/offline_service.dart';

/// Singleton owner of probes + state machine. The provider is intentionally
/// `Provider` (not `autoDispose`) so the controller survives screen
/// navigation; it's an app-lifetime object.
final serviceStatusControllerProvider =
    Provider<ServiceStatusController>((ref) {
  final controller = ServiceStatusController.instance;
  ref.onDispose(controller.dispose);
  return controller;
});

/// Live [ServiceStatusSnapshot] stream for the UI.
///
/// Widgets watch this — they never touch the controller directly. Action
/// methods (`forceProbe`) are exposed via `ref.read(serviceStatusController
/// Provider).forceProbe()`.
final serviceStatusProvider =
    StreamProvider<ServiceStatusSnapshot>((ref) async* {
  final controller = ref.watch(serviceStatusControllerProvider);
  yield controller.current;
  yield* controller.stream;
});

/// Live count of items in the OfflineService sync queue. Drives the
/// "N changes will sync" hint on the banner and the per-item list on the
/// detail sheet.
final pendingSyncCountProvider = StreamProvider<int>((ref) async* {
  final service = OfflineService.instance;
  yield service.pendingSyncs.length;
  yield* service.queueStream.map((q) => q.length);
});

/// Live list of pending syncs for the detail sheet.
final pendingSyncListProvider = StreamProvider<List<PendingSync>>((ref) async* {
  final service = OfflineService.instance;
  yield service.pendingSyncs;
  yield* service.queueStream;
});

/// Last successful drain timestamp. `null` until the first drain.
final lastSyncAtProvider = StreamProvider<DateTime?>((ref) async* {
  final service = OfflineService.instance;
  yield service.lastSuccessfulSyncAt;
  yield* service.lastSyncStream;
});

/// Derived health of the pending queue: how many items, how many are parked
/// needing attention, and how old the oldest one is. Drives the stale-queue
/// escalation banner and the offline-management summary.
@immutable
class PendingSyncHealth {
  const PendingSyncHealth({
    required this.total,
    required this.needsAttentionCount,
    required this.oldestPendingAt,
  });

  final int total;
  final int needsAttentionCount;
  final DateTime? oldestPendingAt;

  bool get hasNeedsAttention => needsAttentionCount > 0;
  bool get hasPending => total > 0;

  Duration? get oldestAge => oldestPendingAt == null
      ? null
      : DateTime.now().difference(oldestPendingAt!);

  /// The oldest item has been waiting past the stale threshold (48h).
  bool get isStale {
    final age = oldestAge;
    return age != null && age >= OfflineService.staleThreshold;
  }

  /// Whether the UI should escalate (red banner): something is parked, or the
  /// queue has been stuck for too long — surfaced even on a healthy
  /// connection, which the connectivity banner alone would hide.
  bool get shouldEscalate => hasNeedsAttention || isStale;

  /// Keep every unsynced write visible, even when Firebase is reachable.
  /// A healthy connection does not mean the queue itself is empty.
  bool get shouldSurface => hasPending;
}

PendingSyncHealth _healthFrom(List<PendingSync> queue) {
  DateTime? oldest;
  var attention = 0;
  for (final p in queue) {
    if (p.needsAttention) attention++;
    if (oldest == null || p.createdAt.isBefore(oldest)) oldest = p.createdAt;
  }
  return PendingSyncHealth(
    total: queue.length,
    needsAttentionCount: attention,
    oldestPendingAt: oldest,
  );
}

/// Live [PendingSyncHealth] derived from the queue stream.
final pendingSyncHealthProvider =
    StreamProvider<PendingSyncHealth>((ref) async* {
  final service = OfflineService.instance;
  yield _healthFrom(service.pendingSyncs);
  yield* service.queueStream.map(_healthFrom);
});

/// Live diagnostic log of the last ~20 sync attempts.
final syncHistoryProvider =
    StreamProvider<List<SyncHistoryEntry>>((ref) async* {
  final service = OfflineService.instance;
  yield service.syncHistory;
  yield* service.historyStream;
});
