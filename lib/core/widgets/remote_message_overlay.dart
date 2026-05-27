import 'package:flutter/material.dart';

import 'remote_message_banner.dart';

/// Outermost overlay (above [ServiceStatusOverlay] / `ImpersonationOverlay`).
/// Hidden when there's no active message — critical messages take visual
/// priority over both impersonation chrome and the service-status banner.
class RemoteMessageOverlay extends StatelessWidget {
  const RemoteMessageOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        const RemoteMessageBanner(),
        Expanded(child: child),
      ],
    );
  }
}
