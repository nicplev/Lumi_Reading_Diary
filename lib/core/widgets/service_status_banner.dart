import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/service_status_provider.dart';
import '../models/service_status.dart';
import '../routing/app_router.dart' show rootNavigatorKey;
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import 'service_status_sheet.dart';

/// Slim global banner driven by `serviceStatusProvider`.
///
/// Renders nothing while healthy or while the bootstrap probe is still
/// `unknown`. Otherwise floats a soft, rounded status card over the top of the
/// app (it overlays — it doesn't push the layout down). Tap opens
/// [ServiceStatusSheet].
class ServiceStatusBanner extends ConsumerWidget {
  const ServiceStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serviceStatusProvider).value;
    final health = ref.watch(pendingSyncHealthProvider).value;

    // Healthy / still-booting connection: normally render nothing — but a
    // queue that's been stuck past the stale threshold (48h) or has parked
    // items must still surface here, which the connectivity-driven banner
    // would otherwise hide.
    if (snapshot == null || !snapshot.shouldShowBanner) {
      if (health != null && health.shouldEscalate) {
        return _StaleEscalationBar(health: health);
      }
      return const SizedBox.shrink();
    }

    final visuals = _visualsFor(snapshot.status);

    return _StatusCard(
      icon: visuals.icon,
      accent: visuals.accent,
      primary: visuals.primary,
      onTap: () => _openStatusSheet(context),
    );
  }

  _BannerVisuals _visualsFor(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.degraded:
        return const _BannerVisuals(
          slim: true,
          accent: LumiTokens.yellow,
          icon: Icons.cloud_queue,
          primary: 'Connection is slow — your reading still saves.',
        );
      case ServiceStatus.firebaseDown:
        return const _BannerVisuals(
          slim: false,
          accent: LumiTokens.yellow,
          icon: Icons.sync_problem,
          primary: 'Lumi service unavailable',
        );
      case ServiceStatus.offline:
        return const _BannerVisuals(
          slim: false,
          accent: LumiTokens.orange,
          icon: Icons.cloud_off,
          primary: "You're offline",
        );
      case ServiceStatus.healthy:
      case ServiceStatus.unknown:
        return const _BannerVisuals(
          slim: true,
          accent: LumiTokens.green,
          icon: Icons.check_circle_outline,
          primary: '',
        );
    }
  }
}

class _BannerVisuals {
  const _BannerVisuals({
    required this.slim,
    required this.accent,
    required this.icon,
    required this.primary,
  });
  final bool slim;
  final Color accent;
  final IconData icon;
  final String primary;
}

/// A soft, rounded, opaque status card. Floats with a gentle shadow and a
/// tinted icon chip — calm enough not to pull the user out of the app, but
/// clearly tappable for details.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.accent,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Skinny single-line pill: a quiet, glanceable notice. Tap opens the full
    // details sheet (the "expanded" view), so the bar itself stays minimal.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            child: Container(
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                border: Border.all(color: LumiTokens.rule),
                boxShadow: LumiTokens.shadowCard,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(icon, color: accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      primary,
                      style: LumiType.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right,
                      size: 16, color: LumiTokens.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens [ServiceStatusSheet] through the root navigator's overlay.
///
/// The banner is mounted by `MaterialApp.router.builder` *above* the
/// Navigator, so its own context has no Navigator ancestor. Routing the modal
/// through the root overlay (always a Navigator descendant) avoids the
/// "context does not include a Navigator" crash.
void _openStatusSheet(BuildContext context) {
  final navContext = rootNavigatorKey.currentState?.overlay?.context;
  if (navContext == null) return;
  showModalBottomSheet<void>(
    context: navContext,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ServiceStatusSheet(),
  );
}

/// Escalation card shown when the connection is healthy but the sync queue is
/// stuck: either an item is parked needing attention, or the oldest pending
/// write has been waiting past the 48h stale threshold. Tapping opens the
/// status sheet with its "Try syncing now" action.
class _StaleEscalationBar extends StatelessWidget {
  const _StaleEscalationBar({required this.health});

  final PendingSyncHealth health;

  @override
  Widget build(BuildContext context) {
    return _StatusCard(
      icon: Icons.error_outline,
      accent: LumiTokens.red,
      primary: _title(health),
      onTap: () => _openStatusSheet(context),
    );
  }

  String _title(PendingSyncHealth h) {
    if (h.hasNeedsAttention) {
      final n = h.needsAttentionCount;
      return n == 1
          ? "1 reading log couldn't sync"
          : "$n reading logs couldn't sync";
    }
    return "Some reading logs haven't synced";
  }
}
