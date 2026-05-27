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

final remoteMessageControllerProvider =
    Provider<RemoteMessageController?>((ref) {
  if (!isRemoteMessageConfigured) return null;
  final controller =
      RemoteMessageController.ensureInstance(Uri.parse(_statusWorkerUrl));
  ref.onDispose(controller.dispose);
  return controller;
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
