import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/offline_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

/// Screen for managing offline data and sync settings
/// Allows users to view cached data, manage storage, and configure sync
class OfflineManagementScreen extends StatefulWidget {
  const OfflineManagementScreen({super.key});

  @override
  State<OfflineManagementScreen> createState() =>
      _OfflineManagementScreenState();
}

class _OfflineManagementScreenState extends State<OfflineManagementScreen> {
  bool _autoSyncEnabled = true;
  bool _wifiOnlySync = false;
  int _cacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
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
            _buildStatusCard(),
            LumiGap.s,
            _buildPendingSyncCard(),
            LumiGap.s,
            _buildSyncSettingsCard(),
            LumiGap.s,
            _buildCacheManagementCard(),
            LumiGap.s,
            _buildBandwidthCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        final isOnline = offlineService.isOnline;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: LumiPadding.allXS,
                        decoration: BoxDecoration(
                          color: isOnline ? AppColors.success : AppColors.warmOrange,
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
                                color: isOnline
                                    ? AppColors.success.withValues(alpha: 0.8)
                                    : AppColors.warmOrange.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (!isOnline) ...[
                    LumiGap.s,
                    Container(
                      padding: LumiPadding.allXS,
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: LumiBorders.small,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.warmOrange,
                          ),
                          LumiGap.horizontalXS,
                          Expanded(
                            child: Text(
                              'You can continue using the app. Your changes will be saved and synced when you\'re back online.',
                              style: LumiTextStyles.bodySmall(
                                color: AppColors.warmOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingSyncCard() {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        final pendingSyncs = offlineService.pendingSyncs;

        return LumiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pending_actions, color: AppColors.rosePink),
                  LumiGap.horizontalXS,
                  Text(
                    'Pending Changes',
                    style: LumiTextStyles.h3(),
                  ),
                ],
              ),
              LumiGap.s,
              if (pendingSyncs.isEmpty)
                Center(
                  child: Padding(
                    padding: LumiPadding.allM,
                    child: Column(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 48,
                          color: AppColors.success,
                        ),
                        LumiGap.xs,
                        Text(
                          'All changes synced!',
                          style: LumiTextStyles.h3(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Text(
                  '${pendingSyncs.length} change${pendingSyncs.length == 1 ? "" : "s"} waiting to sync',
                  style: LumiTextStyles.bodyLarge(),
                ),
                LumiGap.xs,
                ...pendingSyncs.take(5).map((sync) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: LumiSpacing.xs),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.warmOrange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        LumiGap.horizontalXS,
                        Expanded(
                          child: Text(
                            '${sync.action} ${sync.type}',
                            style: LumiTextStyles.body(),
                          ),
                        ),
                        Text(
                          _formatTimestamp(sync.createdAt),
                          style: LumiTextStyles.bodySmall(
                            color: AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (pendingSyncs.length > 5)
                  Padding(
                    padding: EdgeInsets.only(top: LumiSpacing.xs),
                    child: Text(
                      '...and ${pendingSyncs.length - 5} more',
                      style: LumiTextStyles.bodySmall(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                if (offlineService.isOnline) ...[
                  LumiGap.s,
                  SizedBox(
                    width: double.infinity,
                    child: LumiPrimaryButton(
                      onPressed: () {
                        // Manual sync trigger
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Syncing changes...'),
                            backgroundColor: AppColors.rosePink,
                          ),
                        );
                      },
                      text: 'Sync Now',
                      icon: Icons.sync,
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncSettingsCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text(
                'Sync Settings',
                style: LumiTextStyles.h3(),
              ),
            ],
          ),
          LumiGap.s,
          SwitchListTile(
            title: Text('Automatic Sync', style: LumiTextStyles.body()),
            subtitle: Text(
              'Sync changes automatically when online',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            value: _autoSyncEnabled,
            activeTrackColor: AppColors.rosePink.withValues(alpha: 0.5),
            activeThumbColor: AppColors.rosePink,
            onChanged: (value) {
              setState(() => _autoSyncEnabled = value);
              _saveSetting('autoSync', value);
            },
          ),
          SwitchListTile(
            title: Text('Wi-Fi Only', style: LumiTextStyles.body()),
            subtitle: Text(
              'Only sync when connected to Wi-Fi',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            value: _wifiOnlySync,
            activeTrackColor: AppColors.rosePink.withValues(alpha: 0.5),
            activeThumbColor: AppColors.rosePink,
            onChanged: (value) {
              setState(() => _wifiOnlySync = value);
              _saveSetting('wifiOnly', value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCacheManagementCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storage, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text(
                'Cache Management',
                style: LumiTextStyles.h3(),
              ),
            ],
          ),
          LumiGap.s,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cache Size', style: LumiTextStyles.body()),
              Text(
                _formatBytes(_cacheSize),
                style: LumiTextStyles.bodyLarge(),
              ),
            ],
          ),
          LumiGap.s,
          SizedBox(
            width: double.infinity,
            child: LumiSecondaryButton(
              onPressed: _clearCache,
              text: 'Clear Offline Cache',
              icon: Icons.delete_outline,
            ),
          ),
          LumiGap.xs,
          Text(
            'This will remove all offline data. Changes will need to be re-downloaded.',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandwidthCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.network_check, color: AppColors.rosePink),
              LumiGap.horizontalXS,
              Text(
                'Bandwidth Usage',
                style: LumiTextStyles.h3(),
              ),
            ],
          ),
          LumiGap.s,
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
              LumiGap.horizontalXS,
              Expanded(
                child: Text(
                  'The app automatically optimizes data usage when syncing. Images are compressed and only essential data is downloaded.',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM dd').format(timestamp);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  Future<void> _loadSettings() async {
    // Load settings from storage
    // This is simplified - in production would load from Hive
    setState(() {
      _cacheSize = 2500000; // Example: 2.5 MB
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    // Save to storage
    // This is simplified - in production would save to Hive
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: LumiBorders.shapeLarge,
        title: Text('Clear Offline Cache?', style: LumiTextStyles.h3()),
        content: Text(
          'This will remove all offline data. You\'ll need to be online to download it again. Any pending changes will be lost.',
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

    if (confirmed == true) {
      // Clear cache
      // This is simplified - in production would clear Hive boxes

      setState(() {
        _cacheSize = 0;
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cache cleared successfully'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
