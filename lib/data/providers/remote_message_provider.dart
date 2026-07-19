import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/remote_message.dart';
import '../../core/services/remote_message_controller.dart';

/// Production status worker endpoint, set with
/// `--dart-define=LUMI_STATUS_WORKER_URL=https://lumi-status-worker.<your-zone>.workers.dev/status`.
///
/// Falls back to a sentinel that any UI gating off [isConfigured] will
/// notice so we never silently hit a placeholder URL.
const String _statusWorkerUrl = String.fromEnvironment(
  'LUMI_STATUS_WORKER_URL',
  defaultValue: '',
);

bool get isRemoteMessageConfigured => _statusWorkerUrl.isNotEmpty;

/// Parsed endpoint shared by bootstrap and Riverpod. Bootstrap must create
/// and initialize the singleton before the widget tree mounts; otherwise the
/// provider would create an inert controller after startup had already tried
/// (and failed) to read [RemoteMessageController.instance].
Uri? get remoteMessageEndpoint {
  if (_statusWorkerUrl.isEmpty) return null;
  return Uri.tryParse(_statusWorkerUrl);
}

final remoteMessageControllerProvider =
    Provider<RemoteMessageController?>((ref) {
  final endpoint = remoteMessageEndpoint;
  if (endpoint == null) return null;
  final controller = RemoteMessageController.ensureInstance(endpoint);
  ref.onDispose(controller.dispose);
  return controller;
});

/// Whether the independent status/version endpoint is usable. A cached
/// response counts as available during a transient outage because it still
/// carries the last known minimum-version policy. With no cache, transport
/// failures are identified separately so startup can continue while the
/// controller retries; invalid policy/configuration remains unavailable.
final remoteMessageConfigStateProvider =
    StreamProvider<RemoteMessageConfigState>((ref) async* {
  final controller = ref.watch(remoteMessageControllerProvider);
  if (controller == null) {
    yield RemoteMessageConfigState.unavailable;
    return;
  }
  yield controller.configState;
  yield* controller.configStateStream;
});

/// Live remote message stream for the UI. Emits `null` when the controller
/// is unconfigured or the Worker has no active message.
final remoteMessageProvider = StreamProvider<RemoteMessage?>((ref) async* {
  final controller = ref.watch(remoteMessageControllerProvider);
  if (controller == null) {
    yield null;
    return;
  }
  yield controller.current;
  yield* controller.stream;
});

/// Whether the user has dismissed the message currently in play. Watching
/// this lets the banner hide itself the moment the X is tapped.
final remoteMessageDismissedProvider = Provider<bool>((ref) {
  final controller = ref.watch(remoteMessageControllerProvider);
  final message = ref.watch(remoteMessageProvider).value;
  if (controller == null || message == null || !message.isVisible) {
    return false;
  }
  return controller.isDismissed(message);
});
