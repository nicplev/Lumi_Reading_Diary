import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers/service_status_provider.dart';
import '../../services/offline_service.dart';
import '../models/service_status.dart';
import '../theme/app_colors.dart';
import '../../theme/lumi_tokens.dart';
import 'lumi/lumi_toast.dart';

/// Bottom sheet opened when the user taps [ServiceStatusBanner].
///
/// Shows per-layer reachability, the pending-write queue, last sync time,
/// and a manual "Try syncing now" trigger.
class ServiceStatusSheet extends ConsumerWidget {
  const ServiceStatusSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serviceStatusProvider).value;
    final pending = ref.watch(pendingSyncListProvider).value ?? const [];
    final lastSync = ref.watch(lastSyncAtProvider).value;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: LumiTokens.rule,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Connection status',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(height: 16),
            _LayersCard(snapshot: snapshot, lastSync: lastSync),
            const SizedBox(height: 20),
            if (pending.isNotEmpty) ...[
              Text(
                pending.length == 1
                    ? '1 change waiting to sync'
                    : '${pending.length} changes waiting to sync',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
              const SizedBox(height: 8),
              ...pending.take(8).map((p) => _PendingRow(item: p)),
              if (pending.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '+${pending.length - 8} more…',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.charcoal.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            _SyncButton(snapshot: snapshot),
          ],
        ),
      ),
    );
  }
}

class _LayersCard extends StatelessWidget {
  const _LayersCard({required this.snapshot, required this.lastSync});

  final ServiceStatusSnapshot? snapshot;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _LayerRow(
            label: 'Internet',
            value: _internetLabel(s),
            ok: s?.internetReachable ?? false,
          ),
          const Divider(height: 16),
          _LayerRow(
            label: 'Lumi service',
            value: _firebaseLabel(s),
            ok: s?.firebaseReachable ?? false,
          ),
          const Divider(height: 16),
          _LayerRow(
            label: 'Last successful sync',
            value: _formatLastSync(lastSync),
            ok: lastSync != null,
            neutral: true,
          ),
        ],
      ),
    );
  }

  String _internetLabel(ServiceStatusSnapshot? s) {
    if (s == null) return 'Checking…';
    if (!s.deviceConnected) return 'No network';
    return s.internetReachable ? 'Connected' : 'Unreachable';
  }

  String _firebaseLabel(ServiceStatusSnapshot? s) {
    if (s == null) return 'Checking…';
    if (!s.internetReachable) return 'Skipped';
    return s.firebaseReachable ? 'Connected' : 'Unreachable';
  }

  String _formatLastSync(DateTime? at) {
    if (at == null) return 'Never';
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 60) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.label,
    required this.value,
    required this.ok,
    this.neutral = false,
  });

  final String label;
  final String value;
  final bool ok;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final dotColor = neutral
        ? AppColors.charcoal.withValues(alpha: 0.4)
        : (ok ? LumiTokens.green : LumiTokens.orange);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.charcoal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.charcoal.withValues(alpha: 0.8),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.item});
  final PendingSync item;

  @override
  Widget build(BuildContext context) {
    final attention = item.needsAttention;
    final err = item.lastError;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                attention ? Icons.error_outline : _iconFor(item.type),
                size: 16,
                color: attention
                    ? AppColors.error
                    : AppColors.charcoal.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  attention
                      ? "${_labelFor(item.type)} · couldn't sync"
                      : _labelFor(item.type),
                  style: TextStyle(
                    fontSize: 13,
                    color: attention ? AppColors.error : AppColors.charcoal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _formatRelative(item.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (err != null && err.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2),
              child: Text(
                friendlyOfflineSyncError(err),
                style: TextStyle(
                  fontSize: 11,
                  color: (attention ? AppColors.error : AppColors.charcoal)
                      .withValues(alpha: 0.7),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  IconData _iconFor(SyncType type) {
    switch (type) {
      case SyncType.readingLog:
        return Icons.menu_book_outlined;
      case SyncType.comprehensionAudioUpload:
        return Icons.graphic_eq_outlined;
      case SyncType.parentComment:
        return Icons.chat_bubble_outline;
      case SyncType.commentReply:
        return Icons.reply_outlined;
      case SyncType.parentPrefs:
        return Icons.notifications_none;
      case SyncType.student:
        return Icons.person_outline;
      case SyncType.allocation:
        return Icons.assignment_outlined;
      case SyncType.childFeeling:
        return Icons.sentiment_satisfied_outlined;
      case SyncType.allocationAssignment:
        return Icons.menu_book_outlined;
    }
  }

  String _labelFor(SyncType type) {
    switch (type) {
      case SyncType.readingLog:
        return 'Reading log';
      case SyncType.comprehensionAudioUpload:
        return 'Comprehension recording';
      case SyncType.parentComment:
        return 'Parent comment';
      case SyncType.commentReply:
        return 'Comment reply';
      case SyncType.parentPrefs:
        return 'Notification settings';
      case SyncType.student:
        return 'Child profile';
      case SyncType.allocation:
        return 'Allocation';
      case SyncType.childFeeling:
        return 'Reading feeling';
      case SyncType.allocationAssignment:
        return 'Book assignment';
    }
  }

  String _formatRelative(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 60) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m';
    if (delta.inHours < 24) return '${delta.inHours}h';
    return '${delta.inDays}d';
  }
}

class _SyncButton extends ConsumerStatefulWidget {
  const _SyncButton({required this.snapshot});
  final ServiceStatusSnapshot? snapshot;

  @override
  ConsumerState<_SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends ConsumerState<_SyncButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _busy ? null : _trigger,
        style: FilledButton.styleFrom(
          backgroundColor: LumiTokens.green,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation(AppColors.white),
                ),
              )
            : const Text('Try syncing now',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                )),
      ),
    );
  }

  Future<void> _trigger() async {
    setState(() => _busy = true);
    final before = OfflineService.instance.pendingSyncs.length;
    try {
      final controller = ref.read(serviceStatusControllerProvider);
      await controller.forceProbe();
      await OfflineService.instance.triggerSync(retryParked: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final after = OfflineService.instance.pendingSyncs.length;
    final synced = (before - after).clamp(0, before);
    final String msg;
    if (after == 0) {
      msg = synced == 0
          ? 'Nothing to sync'
          : 'All $synced change${synced == 1 ? "" : "s"} synced successfully';
    } else {
      msg = '$synced synced · $after still waiting';
    }
    showLumiToast(message: msg, type: LumiToastType.info);
  }
}
