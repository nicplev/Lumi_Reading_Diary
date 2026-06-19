import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../data/providers/service_status_provider.dart';
import '../../services/offline_service.dart';

/// Parent-facing "offline & sync" page. Reachable from the parent profile.
///
/// Lightweight wrapper around the providers in [service_status_provider.dart]
/// — the heavier diagnostic detail lives in [ServiceStatusScreen]. This
/// screen exists because parents looking for "what data is on my phone"
/// expect a "Clear offline cache" affordance that's intentionally absent
/// from the system-status surface.
class OfflineManagementScreen extends ConsumerWidget {
  const OfflineManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serviceStatusProvider).value;
    final pending = ref.watch(pendingSyncListProvider).value ?? const [];
    final isOnline = snapshot?.canWriteToFirebase ?? false;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Offline & Sync', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(isOnline: isOnline),
            LumiGap.s,
            _PendingCard(pending: pending, canSync: isOnline),
            LumiGap.s,
            const _SyncHistoryCard(),
            LumiGap.s,
            _CacheCard(),
            LumiGap.s,
            LumiCard(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune, color: AppColors.rosePink),
                title: Text('Full connection diagnostics',
                    style: LumiTextStyles.body()),
                subtitle: Text(
                  'Per-layer reachability, last sync, latency.',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.of(context).pushNamed('/settings/service-status'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isOnline
            ? AppColors.success.withValues(alpha: 0.1)
            : AppColors.warmOrange.withValues(alpha: 0.1),
        borderRadius: LumiBorders.large,
      ),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: LumiPadding.allS,
          child: Row(
            children: [
              Container(
                padding: LumiPadding.allXS,
                decoration: BoxDecoration(
                  color:
                      isOnline ? AppColors.success : AppColors.warmOrange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: AppColors.white,
                  size: 32,
                ),
              ),
              LumiGap.horizontalS,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? 'Connected' : 'Offline',
                      style: LumiTextStyles.h2(
                        color: isOnline
                            ? AppColors.success
                            : AppColors.warmOrange,
                      ),
                    ),
                    LumiGap.xxs,
                    Text(
                      isOnline
                          ? 'All changes are being synced'
                          : 'Changes will sync when connected',
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.pending, required this.canSync});
  final List<PendingSync> pending;
  final bool canSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text('Pending changes', style: LumiTextStyles.h3()),
            ],
          ),
          LumiGap.s,
          if (pending.isEmpty)
            Center(
              child: Padding(
                padding: LumiPadding.allM,
                child: Column(
                  children: [
                    const Icon(Icons.check_circle,
                        size: 48, color: AppColors.success),
                    LumiGap.xs,
                    Text(
                      'All changes synced!',
                      style: LumiTextStyles.h3(color: AppColors.success),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text(
              '${pending.length} change${pending.length == 1 ? "" : "s"} '
              'waiting to sync',
              style: LumiTextStyles.bodyLarge(),
            ),
            LumiGap.xs,
            ...pending.take(5).map(
                  (sync) => _PendingDetailRow(
                    sync: sync,
                    label: _syncTypeLabel(sync.type),
                    timeLabel: _formatTimestamp(sync.createdAt),
                  ),
                ),
            if (pending.length > 5)
              Padding(
                padding: EdgeInsets.only(top: LumiSpacing.xs),
                child: Text(
                  '…and ${pending.length - 5} more',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.6),
                  ),
                ),
              ),
            LumiGap.s,
            SizedBox(
              width: double.infinity,
              child: LumiPrimaryButton(
                onPressed: !canSync
                    ? null
                    : () async {
                        final before =
                            OfflineService.instance.pendingSyncs.length;
                        await ref
                            .read(serviceStatusControllerProvider)
                            .forceProbe();
                        await OfflineService.instance.triggerSync();
                        if (!context.mounted) return;
                        final after =
                            OfflineService.instance.pendingSyncs.length;
                        final synced = (before - after).clamp(0, before);
                        final String msg;
                        if (after == 0) {
                          msg = synced == 0
                              ? 'Nothing to sync'
                              : 'All $synced change${synced == 1 ? "" : "s"} '
                                  'synced successfully';
                        } else {
                          msg = '$synced synced · $after still waiting';
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                      },
                text: 'Sync now',
                icon: Icons.sync,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime t) {
    final delta = DateTime.now().difference(t);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inHours < 1) return '${delta.inMinutes}m ago';
    if (delta.inDays < 1) return '${delta.inHours}h ago';
    return DateFormat('MMM dd').format(t);
  }
}

class _CacheCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storage, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text('Cache management', style: LumiTextStyles.h3()),
            ],
          ),
          LumiGap.xs,
          Text(
            "Removes your offline copies. We'll re-download when you're back "
            "online. Pending changes will be lost.",
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
          LumiGap.s,
          SizedBox(
            width: double.infinity,
            child: LumiSecondaryButton(
              onPressed: () => _confirmClear(context),
              text: 'Clear offline cache',
              icon: Icons.delete_outline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: LumiBorders.shapeLarge,
        title: Text('Clear offline cache?', style: LumiTextStyles.h3()),
        content: Text(
          "This will remove all offline data. You'll need to be online "
          "to download it again. Any pending changes will be lost.",
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            text: 'Cancel',
          ),
          LumiTextButton(
            onPressed: () => Navigator.of(context).pop(true),
            text: 'Clear',
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await OfflineService.instance.clearLocalData();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache cleared')),
    );
  }
}

String _syncTypeLabel(SyncType type) {
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
  }
}

String _relativeAge(DateTime t) {
  final delta = DateTime.now().difference(t);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) return '${delta.inMinutes}m ago';
  if (delta.inDays < 1) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

/// A single pending item, with failure/retry detail and a dismiss affordance
/// for items parked needing attention.
class _PendingDetailRow extends StatelessWidget {
  const _PendingDetailRow({
    required this.sync,
    required this.label,
    required this.timeLabel,
  });

  final PendingSync sync;
  final String label;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final attention = sync.needsAttention;
    final dotColor = attention ? AppColors.error : AppColors.warmOrange;

    String? detail;
    if (attention) {
      detail = sync.lastError == null
          ? "Couldn't sync"
          : "Couldn't sync — ${sync.lastError}";
    } else if (sync.retryCount > 0) {
      detail = 'Retrying… (attempt ${sync.retryCount})';
    }

    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              LumiGap.horizontalXS,
              Expanded(child: Text(label, style: LumiTextStyles.body())),
              Text(
                timeLabel,
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      detail,
                      style: LumiTextStyles.bodySmall(
                        color: attention
                            ? AppColors.error
                            : AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  if (attention)
                    GestureDetector(
                      onTap: () async {
                        await OfflineService.instance.dismissPending(sync.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Removed from queue')),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          'Dismiss',
                          style: LumiTextStyles.bodySmall(
                            color: AppColors.rosePink,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Diagnostic log of the last ~20 sync attempts — the single most useful
/// surface for investigating a real "never synced" report.
class _SyncHistoryCard extends ConsumerWidget {
  const _SyncHistoryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(syncHistoryProvider).value ??
        const <SyncHistoryEntry>[];

    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text('Sync history', style: LumiTextStyles.h3()),
            ],
          ),
          LumiGap.s,
          if (history.isEmpty)
            Text(
              'No sync attempts yet.',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
            )
          else
            // Most recent first.
            ...history.reversed.map((e) => _HistoryRow(entry: e)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SyncHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _visual(entry.result);
    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          LumiGap.horizontalXS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_syncTypeLabel(entry.type)} · ${_resultLabel(entry.result)}',
                  style: LumiTextStyles.bodySmall(),
                ),
                if (entry.error != null)
                  Text(
                    entry.error!,
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          LumiGap.horizontalXS,
          Text(
            _relativeAge(entry.at),
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _visual(SyncResult result) {
    switch (result) {
      case SyncResult.success:
        return (Icons.check_circle, AppColors.success);
      case SyncResult.transientFail:
        return (Icons.sync_problem, AppColors.warmOrange);
      case SyncResult.permanentFail:
        return (Icons.error, AppColors.error);
      case SyncResult.integrityFail:
        return (Icons.gpp_bad, AppColors.error);
    }
  }

  String _resultLabel(SyncResult result) {
    switch (result) {
      case SyncResult.success:
        return 'Synced';
      case SyncResult.transientFail:
        return 'Will retry';
      case SyncResult.permanentFail:
        return 'Failed';
      case SyncResult.integrityFail:
        return 'Integrity error';
    }
  }
}
