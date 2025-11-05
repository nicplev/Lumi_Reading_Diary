import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/user_model.dart';
import '../../utils/firestore_migration.dart';

class DatabaseMigrationScreen extends StatefulWidget {
  final UserModel adminUser;

  const DatabaseMigrationScreen({
    super.key,
    required this.adminUser,
  });

  @override
  State<DatabaseMigrationScreen> createState() =>
      _DatabaseMigrationScreenState();
}

class _DatabaseMigrationScreenState extends State<DatabaseMigrationScreen> {
  final FirestoreMigration _migration = FirestoreMigration();

  bool _isMigrating = false;
  bool _isVerifying = false;
  bool _migrationComplete = false;
  bool _verificationComplete = false;

  final List<String> _logs = [];
  final ScrollController _scrollController = ScrollController();

  void _addLog(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    // Auto-scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startMigration() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start Database Migration'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'This will migrate your database to the new nested structure.'),
            SizedBox(height: 16),
            Text('Benefits of migration:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Better performance and scalability'),
            Text('• Simpler queries without complex indexes'),
            Text('• Improved data isolation per school'),
            Text('• Easier backup and export'),
            SizedBox(height: 16),
            Text(
              'Note: Old data will be preserved until you manually delete it.',
              style: TextStyle(color: AppColors.warning),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
            ),
            child: const Text('Start Migration'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isMigrating = true;
      _logs.clear();
    });

    try {
      _addLog('Starting database migration...');
      _addLog('This may take a few minutes depending on data size.');

      await _migration.migrateToNestedStructure();

      _addLog('✅ Migration completed successfully!');
      _addLog('Your data has been migrated to the new structure.');
      _addLog('Old collections are still intact for safety.');

      setState(() {
        _migrationComplete = true;
      });
    } catch (e) {
      _addLog('❌ Migration failed: $e');
      _addLog('Please try again or contact support.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migration failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isMigrating = false;
      });
    }
  }

  Future<void> _verifyMigration() async {
    setState(() {
      _isVerifying = true;
      _logs.clear();
    });

    try {
      _addLog('Starting migration verification...');
      _addLog('Comparing document counts between old and new structures.');

      await _migration.verifyMigration();

      _addLog('✅ Verification completed!');
      _addLog('Check the counts above to ensure all data was migrated.');

      setState(() {
        _verificationComplete = true;
      });
    } catch (e) {
      _addLog('❌ Verification failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  Future<void> _cleanupOldData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Delete Old Collections'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WARNING: This will permanently delete all data from the old collections!',
              style: TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('Only do this after:'),
            Text('• Migration is complete'),
            Text('• Verification shows matching counts'),
            Text('• You have tested the app with new structure'),
            Text('• You have a backup of your data'),
            SizedBox(height: 16),
            Text(
              'This action CANNOT be undone!',
              style: TextStyle(
                  color: AppColors.error, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete Old Data'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Double confirmation for safety
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: const Text(
          'Are you ABSOLUTELY SURE you want to delete all old collections? '
          'Type "DELETE" to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (doubleConfirmed != true) return;

    setState(() {
      _logs.clear();
    });

    try {
      _addLog('Starting cleanup of old collections...');
      _addLog('⚠️ Deleting old data...');

      await _migration.cleanupOldCollections(confirmDelete: true);

      _addLog('✅ Old collections deleted successfully!');
      _addLog('Your database now uses the optimized nested structure.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Old collections deleted successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      _addLog('❌ Cleanup failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleanup failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Database Migration',
          style: TextStyle(color: AppColors.darkGray),
        ),
        iconTheme: const IconThemeData(color: AppColors.darkGray),
      ),
      body: Column(
        children: [
          // Info Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Database Structure Migration',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'This tool migrates your database from a flat structure to an optimized '
                  'nested structure for better performance and scalability.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _isMigrating || _isVerifying ? null : _startMigration,
                    icon: _isMigrating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            _migrationComplete
                                ? Icons.check_circle
                                : Icons.play_arrow,
                          ),
                    label:
                        Text(_isMigrating ? 'Migrating...' : 'Start Migration'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _migrationComplete
                          ? AppColors.success
                          : AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isMigrating || _isVerifying || !_migrationComplete)
                            ? null
                            : _verifyMigration,
                    icon: _isVerifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(
                            _verificationComplete
                                ? Icons.check_circle
                                : Icons.verified_user,
                          ),
                    label: Text(
                        _isVerifying ? 'Verifying...' : 'Verify Migration'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _verificationComplete
                          ? AppColors.success
                          : AppColors.secondaryPurple,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_migrationComplete && _verificationComplete)
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _cleanupOldData,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete Old Collections (Dangerous!)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                ),
              ),
            ),

          // Logs Display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Migration Logs',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (_logs.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear,
                                color: Colors.white70, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() => _logs.clear()),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color textColor = Colors.white70;

                        if (log.contains('✅')) {
                          textColor = Colors.greenAccent;
                        } else if (log.contains('❌')) {
                          textColor = Colors.redAccent;
                        } else if (log.contains('⚠️')) {
                          textColor = Colors.orangeAccent;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            log,
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
