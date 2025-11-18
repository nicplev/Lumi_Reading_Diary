import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/offline_service.dart';

/// Widget that displays the current online/offline status
/// Shows sync progress and pending changes
class OfflineIndicator extends StatefulWidget {
  final bool showDetails;

  const OfflineIndicator({
    super.key,
    this.showDetails = true,
  });

  @override
  State<OfflineIndicator> createState() => _OfflineIndicatorState();
}

class _OfflineIndicatorState extends State<OfflineIndicator> {
  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        if (offlineService.isOnline && offlineService.pendingSyncs.isEmpty) {
          // Online and synced - show nothing or minimal indicator
          return const SizedBox.shrink();
        }

        return _buildIndicator(offlineService);
      },
    );
  }

  Widget _buildIndicator(OfflineService offlineService) {
    final isOnline = offlineService.isOnline;
    final pendingCount = offlineService.pendingSyncs.length;

    if (!widget.showDetails) {
      // Simple icon indicator
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isOnline ? Colors.green : Colors.orange,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isOnline ? Icons.cloud_done : Icons.cloud_off,
          size: 16,
          color: Colors.white,
        ),
      );
    }

    // Detailed banner
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isOnline ? Colors.blue[50] : Colors.orange[50],
        border: Border(
          bottom: BorderSide(
            color: isOnline ? Colors.blue[200]! : Colors.orange[200]!,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.cloud_queue : Icons.cloud_off,
            color: isOnline ? Colors.blue[700] : Colors.orange[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOnline
                      ? (pendingCount > 0
                          ? 'Syncing changes...'
                          : 'Connected')
                      : 'Offline mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isOnline ? Colors.blue[900] : Colors.orange[900],
                  ),
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$pendingCount change${pendingCount == 1 ? "" : "s"} pending',
                    style: TextStyle(
                      fontSize: 11,
                      color: isOnline ? Colors.blue[700] : Colors.orange[700],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (pendingCount > 0 && isOnline)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

/// Small badge showing pending sync count
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        final pendingCount = offlineService.pendingSyncs.length;

        if (pendingCount == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                '$pendingCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Floating action button for manual sync
class SyncFloatingButton extends StatelessWidget {
  const SyncFloatingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<OfflineService>(
      builder: (context, offlineService, child) {
        if (!offlineService.isOnline ||
            offlineService.pendingSyncs.isEmpty) {
          return const SizedBox.shrink();
        }

        return FloatingActionButton.extended(
          onPressed: () async {
            // Trigger manual sync
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Syncing changes...'),
                duration: Duration(seconds: 1),
              ),
            );

            // Note: Sync is automatic, this is just for UX feedback
          },
          icon: const Icon(Icons.sync),
          label: Text('Sync ${offlineService.pendingSyncs.length}'),
          backgroundColor: Colors.orange,
        );
      },
    );
  }
}
