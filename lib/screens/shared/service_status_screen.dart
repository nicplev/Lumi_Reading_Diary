import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/dev_access.dart';
import '../../core/models/remote_message.dart';
import '../../core/models/service_status.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../theme/lumi_tokens.dart';
import '../../data/providers/remote_message_provider.dart';
import '../../data/providers/service_status_provider.dart';
import '../../services/offline_service.dart';

/// Full-screen detail variant of `ServiceStatusSheet`. Reachable from the
/// Settings menu. Adds a diagnostic block useful for support emails.
class ServiceStatusScreen extends ConsumerWidget {
  const ServiceStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(serviceStatusProvider).value;
    final pending = ref.watch(pendingSyncListProvider).value ?? const [];
    final lastSync = ref.watch(lastSyncAtProvider).value;
    final remote = ref.watch(remoteMessageProvider).value;
    final showDevDetails = hasDevAccess();

    return Scaffold(
      backgroundColor: LumiTokens.cream,
      appBar: AppBar(
        title: const Text('Connection status'),
        backgroundColor: LumiTokens.cream,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.charcoal,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            title: 'Reachability',
            child: Column(
              children: [
                _layerRow('Device', snapshot?.deviceConnected ?? false,
                    snapshot?.deviceConnected == true ? 'Online' : 'Offline'),
                const Divider(height: 16),
                _layerRow('Internet', snapshot?.internetReachable ?? false,
                    snapshot?.internetReachable == true
                        ? 'Connected'
                        : 'Unreachable'),
                const Divider(height: 16),
                _layerRow('Lumi service', snapshot?.firebaseReachable ?? false,
                    snapshot?.firebaseReachable == true
                        ? 'Connected'
                        : 'Unreachable'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (showDevDetails) ...[
            _section(
              title: 'Sync',
              child: Column(
                children: [
                  _kv('Last successful sync', _formatLastSync(lastSync)),
                  const SizedBox(height: 8),
                  _kv('Pending changes', pending.length.toString()),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (remote != null) ...[
            _RemoteSection(message: remote),
            const SizedBox(height: 16),
          ],
          if (showDevDetails) ...[
            _DiagnosticsTile(snapshot: snapshot, pending: pending),
            const SizedBox(height: 24),
          ],
          // Plain-language "fix stale data" lever — where someone lands when
          // something looks wrong. Safe: keeps anything still waiting to sync.
          _section(
            title: 'Troubleshooting',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seeing out-of-date information? Clear the locally stored '
                  'copy so the app re-downloads it fresh from the cloud. '
                  'Anything still waiting to sync is kept and will upload as '
                  'normal.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmClearCache(context),
                    icon: const Icon(Icons.cleaning_services_outlined,
                        size: 18),
                    label: const Text('Clear cached data'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                      side: const BorderSide(color: LumiTokens.rule),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: LumiTokens.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () async {
                await ref
                    .read(serviceStatusControllerProvider)
                    .forceProbe();
                await OfflineService.instance.triggerSync();
              },
              child: const Text('Try syncing now',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
                letterSpacing: 0.4,
              )),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _layerRow(String label, bool ok, String value) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: ok ? AppColors.libraryGreen : AppColors.warmOrange,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.charcoal,
              )),
        ),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.charcoal.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }

  Widget _kv(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.charcoal,
              )),
        ),
        Text(value,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.charcoal.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            )),
      ],
    );
  }

  String _formatLastSync(DateTime? at) {
    if (at == null) return 'Never';
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 60) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  /// Safe reset: drops only the cloud-mirror caches (re-downloaded fresh) and
  /// keeps the pending-sync queue + drafts, then kicks off a re-sync.
  Future<void> _confirmClearCache(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: const Text(
          'Clear cached data?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.charcoal,
          ),
        ),
        content: const Text(
          'This removes the local copy of your reading data and re-downloads '
          'it from the cloud. Any changes waiting to sync are kept and will '
          'still upload.',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.charcoal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.charcoal.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: LumiTokens.green,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await OfflineService.instance.clearCachedData();
    await OfflineService.instance.triggerSync();
    if (!context.mounted) return;
    showLumiToast(
      message: 'Cached data cleared — re-downloading from the cloud.',
      type: LumiToastType.info,
    );
  }
}

class _RemoteSection extends StatelessWidget {
  const _RemoteSection({required this.message});
  final RemoteMessage message;

  @override
  Widget build(BuildContext context) {
    final color = switch (message.severity) {
      RemoteMessageSeverity.info => AppColors.skyBlue,
      RemoteMessageSeverity.warn => AppColors.softYellow,
      RemoteMessageSeverity.critical => AppColors.error,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Latest announcement',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
                letterSpacing: 0.4,
              )),
          const SizedBox(height: 10),
          Container(
            width: 6,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 8),
          Text(message.message ?? '',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.charcoal)),
          const SizedBox(height: 8),
          Text(
            'Updated ${_formatTimestamp(message.updatedAt ?? message.fetchedAt)}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 60) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }
}

class _DiagnosticsTile extends StatefulWidget {
  const _DiagnosticsTile({required this.snapshot, required this.pending});
  final ServiceStatusSnapshot? snapshot;
  final List<PendingSync> pending;

  @override
  State<_DiagnosticsTile> createState() => _DiagnosticsTileState();
}

class _DiagnosticsTileState extends State<_DiagnosticsTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: const Text('Diagnostic details',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              )),
          onExpansionChanged: (v) => setState(() => _open = v),
          children: _open ? _diagnosticChildren() : const [],
        ),
      ),
    );
  }

  List<Widget> _diagnosticChildren() {
    final s = widget.snapshot;
    final latency = s?.lastProbeLatency?.inMilliseconds;
    final projectId = _safeProjectId();
    final entries = <_DiagEntry>[
      _DiagEntry('Last probe', s?.checkedAt.toIso8601String() ?? '—'),
      _DiagEntry('Probe latency',
          latency != null ? '${latency}ms' : 'unknown'),
      _DiagEntry('Firebase project', projectId ?? 'unknown'),
      _DiagEntry('Pending queue size', widget.pending.length.toString()),
    ];
    return entries.map((e) => _diagRow(e)).toList();
  }

  String? _safeProjectId() {
    try {
      return Firebase.app().options.projectId;
    } catch (_) {
      return null;
    }
  }

  Widget _diagRow(_DiagEntry e) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(e.label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                )),
          ),
          Expanded(
            child: SelectableText(
              e.value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.charcoal,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagEntry {
  const _DiagEntry(this.label, this.value);
  final String label;
  final String value;
}
