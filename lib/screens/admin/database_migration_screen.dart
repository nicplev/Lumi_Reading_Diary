import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
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
        shape: LumiBorders.shapeLarge,
        title: Text('Start Database Migration', style: LumiTextStyles.h3()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will migrate your database to the new nested structure.',
              style: LumiTextStyles.body(),
            ),
            LumiGap.s,
            Text('Benefits of migration:', style: LumiTextStyles.bodyMedium()),
            LumiGap.xs,
            Text('• Better performance and scalability', style: LumiTextStyles.body()),
            Text('• Simpler queries without complex indexes', style: LumiTextStyles.body()),
            Text('• Improved data isolation per school', style: LumiTextStyles.body()),
            Text('• Easier backup and export', style: LumiTextStyles.body()),
            LumiGap.s,
            Text(
              'Note: Old data will be preserved until you manually delete it.',
              style: LumiTextStyles.body(color: AppColors.warning),
            ),
          ],
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Start Migration',
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
        shape: LumiBorders.shapeLarge,
        title: Text('⚠️ Delete Old Collections', style: LumiTextStyles.h3()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WARNING: This will permanently delete all data from the old collections!',
              style: LumiTextStyles.bodyMedium(color: AppColors.error),
            ),
            LumiGap.s,
            Text('Only do this after:', style: LumiTextStyles.body()),
            Text('• Migration is complete', style: LumiTextStyles.body()),
            Text('• Verification shows matching counts', style: LumiTextStyles.body()),
            Text('• You have tested the app with new structure', style: LumiTextStyles.body()),
            Text('• You have a backup of your data', style: LumiTextStyles.body()),
            LumiGap.s,
            Text(
              'This action CANNOT be undone!',
              style: LumiTextStyles.bodyMedium(color: AppColors.error),
            ),
          ],
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Delete Old Data',
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Double confirmation for safety
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: LumiBorders.shapeLarge,
        title: Text('Final Confirmation', style: LumiTextStyles.h3()),
        content: Text(
          'Are you ABSOLUTELY SURE you want to delete all old collections? '
          'Type "DELETE" to confirm.',
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiPrimaryButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'DELETE',
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
        title: Text(
          'Database Migration',
          style: LumiTextStyles.h2(color: AppColors.charcoal),
        ),
        iconTheme: const IconThemeData(color: AppColors.charcoal),
      ),
      body: Column(
        children: [
          // Info Card
          Container(
            width: double.infinity,
            margin: LumiPadding.allS,
            padding: LumiPadding.allS,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: LumiBorders.medium,
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info, size: 20),
                    LumiGap.xs,
                    Text(
                      'Database Structure Migration',
                      style: LumiTextStyles.bodyMedium(color: AppColors.info),
                    ),
                  ],
                ),
                LumiGap.xs,
                Text(
                  'This tool migrates your database from a flat structure to an optimized '
                  'nested structure for better performance and scalability.',
                  style: LumiTextStyles.bodySmall(),
                ),
              ],
            ),
          ),

          // Action Buttons
          Padding(
            padding: LumiPadding.horizontalS,
            child: Row(
              children: [
                Expanded(
                  child: LumiPrimaryButton(
                    onPressed:
                        _isMigrating || _isVerifying ? null : _startMigration,
                    text: _isMigrating ? 'Migrating...' : 'Start Migration',
                    icon: _migrationComplete
                        ? Icons.check_circle
                        : Icons.play_arrow,
                    isLoading: _isMigrating,
                    isFullWidth: true,
                  ),
                ),
                LumiGap.xs,
                Expanded(
                  child: LumiSecondaryButton(
                    onPressed:
                        (_isMigrating || _isVerifying || !_migrationComplete)
                            ? null
                            : _verifyMigration,
                    text: _isVerifying ? 'Verifying...' : 'Verify Migration',
                    icon: _verificationComplete
                        ? Icons.check_circle
                        : Icons.verified_user,
                    isLoading: _isVerifying,
                    isFullWidth: true,
                  ),
                ),
              ],
            ),
          ),

          if (_migrationComplete && _verificationComplete)
            Padding(
              padding: LumiPadding.allS,
              child: LumiPrimaryButton(
                onPressed: _cleanupOldData,
                text: 'Delete Old Collections (Dangerous!)',
                icon: Icons.delete_forever,
              ),
            ),

          // Logs Display
          Expanded(
            child: Container(
              margin: LumiPadding.allS,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: LumiBorders.small,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: LumiPadding.allXS,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(LumiBorders.radiusSmall),
                        topRight: Radius.circular(LumiBorders.radiusSmall),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Migration Logs',
                          style: LumiTextStyles.bodySmall(color: Colors.white70),
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
                      padding: LumiPadding.allXS,
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
                            style: LumiTextStyles.bodySmall(color: textColor).copyWith(
                              fontFamily: 'monospace',
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
