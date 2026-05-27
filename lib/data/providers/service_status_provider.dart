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
final pendingSyncListProvider =
    StreamProvider<List<PendingSync>>((ref) async* {
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
