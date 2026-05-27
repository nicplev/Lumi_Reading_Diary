import 'package:flutter/material.dart';

import 'service_status_banner.dart';

/// Wraps the routed app with a top-of-screen [ServiceStatusBanner]. The
/// banner self-hides when status is healthy, so this overlay is a no-op
/// on the happy path.
class ServiceStatusOverlay extends StatelessWidget {
  const ServiceStatusOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.max,
      children: [
        const ServiceStatusBanner(),
        Expanded(child: child),
      ],
    );
  }
}
