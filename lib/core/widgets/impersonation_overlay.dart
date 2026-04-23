import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/user_provider.dart';
import 'impersonation_banner.dart';
import 'impersonation_watermark.dart';

/// Wraps the app's root child with the [ImpersonationBanner] and a diagonal
/// watermark whenever a session is active. When inactive, returns [child]
/// unchanged so the normal app layout is untouched.
class ImpersonationOverlay extends ConsumerWidget {
  const ImpersonationOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(impersonationSessionProvider).value;
    if (session == null) return child;

    return Stack(
      children: [
        Column(
          children: [
            const ImpersonationBanner(),
            Expanded(child: child),
          ],
        ),
        Positioned.fill(
          child: ImpersonationWatermark(session: session),
        ),
      ],
    );
  }
}
