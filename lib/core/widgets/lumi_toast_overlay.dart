import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/service_status_provider.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import 'lumi/lumi_toast.dart';

/// Floats [LumiToastController]'s active toasts over the top of the routed app,
/// mirroring [ServiceStatusOverlay]'s Stack approach so toasts overlay content
/// instead of pushing the layout down. Renders nothing when there are no toasts,
/// so it's a no-op on the happy path.
///
/// Mounted once in `main.dart`'s `MaterialApp.router` builder chain, outermost
/// of the overlays, so toasts always paint above app + banner chrome.
class LumiToastOverlay extends ConsumerStatefulWidget {
  const LumiToastOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LumiToastOverlay> createState() => _LumiToastOverlayState();
}

class _LumiToastOverlayState extends ConsumerState<LumiToastOverlay> {
  final LumiToastController _controller = LumiToastController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onToastsChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onToastsChanged);
    super.dispose();
  }

  void _onToastsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final toasts = _controller.toasts;

    // The service-status banner floats in the same top slot. When it (or the
    // pending-queue notice) is showing, drop the toast column below it so the
    // two never overlap.
    final snapshot = ref.watch(serviceStatusProvider).value;
    final health = ref.watch(pendingSyncHealthProvider).value;
    final bannerShowing = (snapshot?.shouldShowBanner ?? false) ||
        (health?.shouldSurface ?? false);

    return Stack(
      children: [
        widget.child,
        if (toasts.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (bannerShowing) const SizedBox(height: 48),
                    for (final toast in toasts)
                      _LumiToastCard(
                        key: ValueKey('lumi-toast-${toast.id}'),
                        data: toast,
                        onDismiss: () => _controller.dismiss(toast.id),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A single bento toast pill. Structurally identical to the service-status
/// `_StatusCard` — opaque paper pill, 1px rule border, soft shadow, tinted
/// leading icon, 13px semibold ink text — but wraps to two lines and can host an
/// optional action instead of the "tap for details" chevron.
class _LumiToastCard extends StatelessWidget {
  const _LumiToastCard({
    super.key,
    required this.data,
    required this.onDismiss,
  });

  final LumiToastData data;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final accent = data.type.accent;

    final pill = Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(data.type.icon, color: accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.message,
              style: LumiType.body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (data.hasAction) ...[
            const SizedBox(width: 8),
            _ToastAction(
              label: data.actionLabel!,
              accent: accent,
              onTap: () {
                data.onAction!.call();
                onDismiss();
              },
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        liveRegion: true,
        container: true,
        label: data.message,
        child: Dismissible(
          key: ValueKey('lumi-toast-dismiss-${data.id}'),
          direction: DismissDirection.up,
          onDismissed: (_) => onDismiss(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
              child: pill,
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(
          begin: -0.25,
          end: 0,
          duration: 260.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Compact accent-coloured action (e.g. "Undo") shown at the trailing edge of a
/// toast. Its own tap wins over the pill's tap-to-dismiss.
class _ToastAction extends StatelessWidget {
  const _ToastAction({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: LumiType.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }
}
