import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/remote_message_provider.dart';
import '../models/remote_message.dart';
import '../theme/app_colors.dart';

/// Out-of-band banner driven by the Cloudflare status worker.
///
/// Sits above [ServiceStatusBanner] in the overlay stack. Hidden unless the
/// fetched message is visible (`id != null`) and not dismissed.
class RemoteMessageBanner extends ConsumerWidget {
  const RemoteMessageBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(remoteMessageProvider).value;
    if (message == null || !message.isVisible) {
      return const SizedBox.shrink();
    }
    final dismissed = ref.watch(remoteMessageDismissedProvider);
    if (dismissed) return const SizedBox.shrink();

    final visuals = _visualsFor(message.severity);

    return SafeArea(
      bottom: false,
      child: Material(
        color: visuals.background,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(visuals.icon, color: visuals.foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message.message ?? '',
                  style: TextStyle(
                    color: visuals.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (message.dismissible)
                IconButton(
                  icon: Icon(Icons.close, color: visuals.foreground, size: 18),
                  splashRadius: 18,
                  tooltip: 'Dismiss',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                  onPressed: () =>
                      _dismiss(ref, message),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(WidgetRef ref, RemoteMessage message) async {
    final controller = ref.read(remoteMessageControllerProvider);
    await controller?.dismiss(message);
    ref.invalidate(remoteMessageDismissedProvider);
  }

  _RemoteVisuals _visualsFor(RemoteMessageSeverity severity) {
    switch (severity) {
      case RemoteMessageSeverity.info:
        return _RemoteVisuals(
          background: AppColors.skyBlue,
          foreground: AppColors.charcoal,
          icon: Icons.info_outline,
        );
      case RemoteMessageSeverity.warn:
        return _RemoteVisuals(
          background: AppColors.softYellow,
          foreground: AppColors.charcoal,
          icon: Icons.notification_important_outlined,
        );
      case RemoteMessageSeverity.critical:
        return _RemoteVisuals(
          background: AppColors.error,
          foreground: AppColors.white,
          icon: Icons.warning_amber_rounded,
        );
    }
  }
}

class _RemoteVisuals {
  const _RemoteVisuals({
    required this.background,
    required this.foreground,
    required this.icon,
  });
  final Color background;
  final Color foreground;
  final IconData icon;
}
