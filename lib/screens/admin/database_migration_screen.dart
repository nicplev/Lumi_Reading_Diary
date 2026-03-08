import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusL)),
        title: Text('Start Database Migration', style: TeacherTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will migrate your database to the new nested structure.',
              style: TeacherTypography.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text('Benefits of migration:', style: TeacherTypography.bodyMedium),
            const SizedBox(height: 4),
            Text('• Better performance and scalability', style: TeacherTypography.bodyMedium),
            Text('• Simpler queries without complex indexes', style: TeacherTypography.bodyMedium),
            Text('• Improved data isolation per school', style: TeacherTypography.bodyMedium),
            Text('• Easier backup and export', style: TeacherTypography.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'Note: Old data will be preserved until you manually delete it.',
              style: TeacherTypography.bodyMedium.copyWith(color: AppColors.warning),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TeacherTypography.bodyMedium.copyWith(color: AppColors.teacherPrimary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const SizedBox.shrink(),
            label: const Text('Start Migration'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
            ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusL)),
        title: Text('⚠️ Delete Old Collections', style: TeacherTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WARNING: This will permanently delete all data from the old collections!',
              style: TeacherTypography.bodyMedium.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 8),
            Text('Only do this after:', style: TeacherTypography.bodyMedium),
            Text('• Migration is complete', style: TeacherTypography.bodyMedium),
            Text('• Verification shows matching counts', style: TeacherTypography.bodyMedium),
            Text('• You have tested the app with new structure', style: TeacherTypography.bodyMedium),
            Text('• You have a backup of your data', style: TeacherTypography.bodyMedium),
            const SizedBox(height: 8),
            Text(
              'This action CANNOT be undone!',
              style: TeacherTypography.bodyMedium.copyWith(color: AppColors.error),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TeacherTypography.bodyMedium.copyWith(color: AppColors.teacherPrimary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const SizedBox.shrink(),
            label: const Text('Delete Old Data'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Double confirmation for safety
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusL)),
        title: Text('Final Confirmation', style: TeacherTypography.h3),
        content: Text(
          'Are you ABSOLUTELY SURE you want to delete all old collections? '
          'Type "DELETE" to confirm.',
          style: TeacherTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TeacherTypography.bodyMedium.copyWith(color: AppColors.teacherPrimary)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const SizedBox.shrink(),
            label: const Text('DELETE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teacherPrimary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
            ),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
        elevation: 0,
        title: const Text(
          'Database Migration',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // Info Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.info, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      'Database Structure Migration',
                      style: TeacherTypography.bodyMedium.copyWith(color: AppColors.info),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'This tool migrates your database from a flat structure to an optimized '
                  'nested structure for better performance and scalability.',
                  style: TeacherTypography.bodySmall,
                ),
              ],
            ),
          ),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isMigrating || _isVerifying) ? null : _startMigration,
                    icon: _isMigrating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.white, strokeWidth: 2))
                        : Icon(_migrationComplete ? Icons.check_circle : Icons.play_arrow),
                    label: Text(_isMigrating ? 'Migrating...' : 'Start Migration'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teacherPrimary,
                      foregroundColor: AppColors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_isMigrating || _isVerifying || !_migrationComplete) ? null : _verifyMigration,
                    icon: _isVerifying
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.teacherPrimary, strokeWidth: 2))
                        : Icon(_verificationComplete ? Icons.check_circle : Icons.verified_user),
                    label: Text(_isVerifying ? 'Verifying...' : 'Verify Migration'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.teacherPrimary,
                      side: const BorderSide(color: AppColors.teacherPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_migrationComplete && _verificationComplete)
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton.icon(
                onPressed: _cleanupOldData,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete Old Collections (Dangerous!)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TeacherDimensions.radiusM)),
                ),
              ),
            ),

          // Logs Display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusS),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(TeacherDimensions.radiusS),
                        topRight: Radius.circular(TeacherDimensions.radiusS),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Migration Logs',
                          style: TeacherTypography.bodySmall.copyWith(color: Colors.white70),
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
                      padding: const EdgeInsets.all(4),
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
                            style: TeacherTypography.bodySmall.copyWith(
                              color: textColor,
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
