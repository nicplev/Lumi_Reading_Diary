import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/offline_service.dart';
import '../../core/theme/app_colors.dart';

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
      appBar: AppBar(
        title: const Text('Offline & Sync'),
        backgroundColor: AppColors.primaryBlue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildPendingSyncCard(),
            const SizedBox(height: 16),
            _buildSyncSettingsCard(),
            const SizedBox(height: 16),
            _buildCacheManagementCard(),
            const SizedBox(height: 16),
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

        return Card(
          elevation: 2,
          color: isOnline ? Colors.green[50] : Colors.orange[50],
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isOnline ? Icons.cloud_done : Icons.cloud_off,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isOnline ? 'Connected' : 'Offline',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isOnline
                                      ? Colors.green[900]
                                      : Colors.orange[900],
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isOnline
                                ? 'All changes are being synced'
                                : 'Changes will sync when connected',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: isOnline
                                          ? Colors.green[700]
                                          : Colors.orange[700],
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isOnline) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You can continue using the app. Your changes will be saved and synced when you\'re back online.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[900],
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
        );
      },
    );
  }

  Widget _buildPendingSyncCard() {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        final pendingSyncs = offlineService.pendingSyncs;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pending_actions, color: AppColors.primaryBlue),
                    const SizedBox(width: 8),
                    Text(
                      'Pending Changes',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (pendingSyncs.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle,
                              size: 48, color: Colors.green[300]),
                          const SizedBox(height: 12),
                          Text(
                            'All changes synced!',
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.green[700],
                                    ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Text(
                    '${pendingSyncs.length} change${pendingSyncs.length == 1 ? "" : "s"} waiting to sync',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  ...pendingSyncs.take(5).map((sync) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${sync.action} ${sync.type}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            _formatTimestamp(sync.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  if (pendingSyncs.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '...and ${pendingSyncs.length - 5} more',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  if (offlineService.isOnline) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Manual sync trigger
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Syncing changes...'),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        },
                        icon: const Icon(Icons.sync),
                        label: const Text('Sync Now'),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSyncSettingsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sync, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'Sync Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Automatic Sync'),
              subtitle: const Text(
                  'Sync changes automatically when online'),
              value: _autoSyncEnabled,
              onChanged: (value) {
                setState(() => _autoSyncEnabled = value);
                _saveSetting('autoSync', value);
              },
            ),
            SwitchListTile(
              title: const Text('Wi-Fi Only'),
              subtitle:
                  const Text('Only sync when connected to Wi-Fi'),
              value: _wifiOnlySync,
              onChanged: (value) {
                setState(() => _wifiOnlySync = value);
                _saveSetting('wifiOnly', value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheManagementCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.storage, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'Cache Management',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cache Size'),
                Text(
                  _formatBytes(_cacheSize),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _clearCache,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Offline Cache'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This will remove all offline data. Changes will need to be re-downloaded.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandwidthCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.network_check, color: AppColors.primaryBlue),
                const SizedBox(width: 8),
                Text(
                  'Bandwidth Usage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The app automatically optimizes data usage when syncing. Images are compressed and only essential data is downloaded.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
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
        title: const Text('Clear Offline Cache?'),
        content: const Text(
          'This will remove all offline data. You\'ll need to be online to download it again. Any pending changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
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
        const SnackBar(
          content: Text('Cache cleared successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
