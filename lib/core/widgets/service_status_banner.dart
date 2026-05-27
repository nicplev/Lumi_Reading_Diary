import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/service_status_provider.dart';
import '../models/service_status.dart';
import '../routing/app_router.dart' show rootNavigatorKey;
import '../theme/app_colors.dart';
import 'service_status_sheet.dart';

/// Slim global banner driven by `serviceStatusProvider`.
///
/// Renders nothing while healthy or while the bootstrap probe is still
/// `unknown`. For `degraded` shows a compact amber strip; for `offline` /
/// `firebaseDown` shows the full banner with a pending-write hint. Tap
/// opens [ServiceStatusSheet].
class ServiceStatusBanner extends ConsumerWidget {
  const ServiceStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serviceStatusProvider).value;
    if (snapshot == null || !snapshot.shouldShowBanner) {
      return const SizedBox.shrink();
    }

    final pendingCount = ref.watch(pendingSyncCountProvider).value ?? 0;
    final visuals = _visualsFor(snapshot.status);

    return SafeArea(
      bottom: false,
      child: Material(
        color: visuals.background,
        child: InkWell(
          onTap: () => _open(context),
          child: Container(
            constraints: BoxConstraints(minHeight: visuals.slim ? 28 : 44),
            decoration: BoxDecoration(
              border: visuals.borderColor != null
                  ? Border(
                      bottom: BorderSide(color: visuals.borderColor!, width: 1))
                  : null,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: visuals.slim ? 4 : 8,
            ),
            child: Row(
              children: [
                Icon(visuals.icon,
                    color: visuals.iconColor, size: visuals.slim ? 16 : 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        visuals.primary,
                        style: TextStyle(
                          color: AppColors.charcoal,
                          fontSize: visuals.slim ? 12 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!visuals.slim && pendingCount > 0)
                        Text(
                          pendingCount == 1
                              ? '1 change will sync when reconnected.'
                              : '$pendingCount changes will sync when '
                                  'reconnected.',
                          style: TextStyle(
                            color: AppColors.charcoal.withValues(alpha: 0.75),
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  visuals.slim ? Icons.chevron_right : Icons.info_outline,
                  size: visuals.slim ? 14 : 16,
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    // The banner is mounted by `MaterialApp.router.builder` *above* the
    // Navigator, so its own context has no Navigator ancestor. Route the
    // modal through the root navigator's overlay (always a Navigator
    // descendant) to avoid the "context does not include a Navigator" crash.
    final navContext = rootNavigatorKey.currentState?.overlay?.context;
    if (navContext == null) return;
    showModalBottomSheet<void>(
      context: navContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ServiceStatusSheet(),
    );
  }

  _BannerVisuals _visualsFor(ServiceStatus status) {
    switch (status) {
      case ServiceStatus.degraded:
        return _BannerVisuals(
          slim: true,
          background: AppColors.softYellow,
          borderColor: null,
          icon: Icons.cloud_queue,
          iconColor: AppColors.darkYellow,
          primary: 'Connection is slow — your reading still saves.',
        );
      case ServiceStatus.firebaseDown:
        return _BannerVisuals(
          slim: false,
          background: AppColors.softYellow,
          borderColor: AppColors.darkYellow,
          icon: Icons.sync_problem,
          iconColor: AppColors.darkYellow,
          primary: 'Lumi service unavailable',
        );
      case ServiceStatus.offline:
        return _BannerVisuals(
          slim: false,
          background: AppColors.warmOrange.withValues(alpha: 0.15),
          borderColor: AppColors.warmOrange,
          icon: Icons.cloud_off,
          iconColor: AppColors.warmOrange,
          primary: "You're offline",
        );
      case ServiceStatus.healthy:
      case ServiceStatus.unknown:
        return _BannerVisuals(
          slim: true,
          background: AppColors.background,
          borderColor: null,
          icon: Icons.check_circle_outline,
          iconColor: AppColors.charcoal,
          primary: '',
        );
    }
  }
}

class _BannerVisuals {
  const _BannerVisuals({
    required this.slim,
    required this.background,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.primary,
  });
  final bool slim;
  final Color background;
  final Color? borderColor;
  final IconData icon;
  final Color iconColor;
  final String primary;
}
