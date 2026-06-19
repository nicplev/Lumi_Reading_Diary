import 'package:flutter/material.dart';

import 'service_status_banner.dart';

/// Floats a [ServiceStatusBanner] over the top of the routed app. Using a
/// [Stack] (not a Column) means the banner overlays the content instead of
/// pushing the whole screen down — and the app's own background fills behind it,
/// so the status-bar area is never a bare black strip. The banner self-hides
/// when status is healthy, so this overlay is a no-op on the happy path.
class ServiceStatusOverlay extends StatelessWidget {
  const ServiceStatusOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ServiceStatusBanner(),
        ),
      ],
    );
  }
}
