import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/feedback_widget.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/offline_service.dart';
import '../../services/reading_level_service.dart';

/// Teacher Settings Screen (Tab 4)
///
/// Production-ready settings with persisted preferences, real navigation,
/// and cache/sync management.
class TeacherSettingsScreen extends StatefulWidget {
  final UserModel user;

  const TeacherSettingsScreen({
    super.key,
    required this.user,
  });

  @override
  State<TeacherSettingsScreen> createState() => _TeacherSettingsScreenState();
}

class _TeacherSettingsScreenState extends State<TeacherSettingsScreen> {
  final ReadingLevelService _readingLevelService = ReadingLevelService();

  // Teacher's classes (for class picker navigation)
  List<ClassModel> _classes = [];
  bool _loadingClasses = true;
  bool _levelsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadReadingLevelOptions();
  }

  Future<void> _loadReadingLevelOptions() async {
    final schoolId = widget.user.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;
    try {
      final options = await _readingLevelService.loadSchoolLevels(schoolId);
      if (!mounted) return;
      setState(() => _levelsEnabled = options.isNotEmpty);
    } catch (_) {}
  }

  Future<void> _loadClasses() async {
    try {
      final schoolId = widget.user.schoolId;
      if (schoolId == null) {
        setState(() => _loadingClasses = false);
        return;
      }
      final snapshot = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('classes')
          .where('teacherIds', arrayContains: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _classes = snapshot.docs
              .map((doc) => ClassModel.fromFirestore(doc))
              .toList();
          _loadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  /// Pick a class (or use the only one) and navigate to a route that requires ClassModel.
  Future<void> _navigateWithClass(String route) async {
    if (_loadingClasses) return;

    if (_classes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No classes assigned to your account.')),
      );
      return;
    }

    ClassModel? selected;
    if (_classes.length == 1) {
      selected = _classes.first;
    } else {
      selected = await _showClassPicker();
    }

    if (selected == null || !mounted) return;

    // Build the extra params based on what the route needs
    final Map<String, dynamic> extra = {'classModel': selected};
    if (route == '/teacher/level-management') {
      extra['teacher'] = widget.user;
    }

    context.push(route, extra: extra);
  }

  Future<ClassModel?> _showClassPicker() async {
    return showModalBottomSheet<ClassModel>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TeacherDimensions.radiusXL),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  child: Text('Select a Class',
                      style: TeacherTypography.h3),
                ),
                const SizedBox(height: 8),
                ..._classes.map(
                  (cls) => ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            AppColors.teacherPrimary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.class_,
                          color: AppColors.teacherPrimary, size: 20),
                    ),
                    title: Text(cls.name,
                        style: TeacherTypography.bodyLarge
                            .copyWith(fontWeight: FontWeight.w600)),
                    subtitle: cls.room != null
                        ? Text('Room ${cls.room}',
                            style: TeacherTypography.caption)
                        : null,
                    onTap: () => Navigator.pop(context, cls),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleClearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        ),
        title: const Text('Clear Cache', style: TeacherTypography.h3),
        content: const Text(
          'This will remove locally cached data older than 30 days. '
          'Your data is safely stored in the cloud.',
          style: TeacherTypography.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TeacherTypography.buttonText
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Clear',
                style: TeacherTypography.buttonText
                    .copyWith(color: AppColors.teacherPrimary)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await OfflineService.instance.clearOldData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cache cleared successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to clear cache.')),
          );
        }
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.teacherPrimary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_stories,
                  color: AppColors.teacherPrimary, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Lumi', style: TeacherTypography.h3),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0',
                style: TeacherTypography.bodyLarge
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            const Text('Reading Tracker for Schools',
                style: TeacherTypography.bodyLarge),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: TeacherTypography.buttonText
                    .copyWith(color: AppColors.teacherPrimary)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        ),
        title: const Text('Sign Out', style: TeacherTypography.h3),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TeacherTypography.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TeacherTypography.buttonText
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out',
                style: TeacherTypography.buttonText
                    .copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseService.instance.signOut();
      if (mounted) {
        context.go('/auth/login');
      }
    }
  }

  Widget _buildSyncStatusTrailing() {
    final status = OfflineService.instance.getSyncStatus();
    final pendingCount = OfflineService.instance.pendingSyncs.length;

    String label;
    Color color;
    switch (status) {
      case SyncStatus.synced:
        label = 'All synced';
        color = AppColors.libraryGreen;
        break;
      case SyncStatus.syncing:
        label = 'Syncing...';
        color = AppColors.teacherPrimary;
        break;
      case SyncStatus.pending:
        label = '$pendingCount pending';
        color = AppColors.warmOrange;
        break;
      case SyncStatus.offline:
        label = 'Offline';
        color = AppColors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // --------------------------------------------------
  // NEW: Log Out Card
  // --------------------------------------------------
  Widget _buildLogOutCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: InkWell(
        onTap: _handleSignOut,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TeacherDimensions.paddingL,
            vertical: TeacherDimensions.paddingM,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.logout_rounded,
                    size: 22, color: AppColors.error),
              ),
              const SizedBox(width: 14),
              Text(
                'Log Out',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------
  // NEW: Version Footer
  // --------------------------------------------------
  Widget _buildVersionFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 20),
      child: Center(
        child: Text(
          'Lumi v1.0.0',
          style: TeacherTypography.caption.copyWith(
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: TeacherTypography.h1)
                .animate()
                .fadeIn(duration: 400.ms)
                .slideY(begin: -0.05, end: 0, curve: Curves.easeOutCubic),

            const SizedBox(height: 20),

            // CLASSROOM section
            TeacherSettingsSection(
              title: 'Classroom',
              items: [
                if (_levelsEnabled)
                  TeacherSettingsItem(
                    icon: Icons.auto_stories,
                    iconBgColor: AppColors.decodableBlue,
                    label: 'Reading Levels',
                    onTap: () =>
                        _navigateWithClass('/teacher/level-management'),
                  ),
                TeacherSettingsItem(
                  icon: Icons.groups,
                  iconBgColor: AppColors.teacherAccent,
                  label: 'Reading Groups',
                  onTap: () => _navigateWithClass('/teacher/reading-groups'),
                ),
                TeacherSettingsItem(
                  icon: Icons.assessment,
                  iconBgColor: AppColors.libraryGreen,
                  label: 'Class Reports',
                  onTap: () => _navigateWithClass('/teacher/class-report'),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: 60.ms)
                .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

            const SizedBox(height: 16),

            // NOTIFICATIONS section
            TeacherSettingsSection(
              title: 'Notifications',
              items: [
                TeacherSettingsItem(
                  icon: Icons.campaign,
                  iconBgColor: AppColors.skyBlue,
                  label: 'Parent/Guardian Notifications',
                  onTap: () {
                    context.push('/teacher/notifications',
                        extra: widget.user);
                  },
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: 120.ms)
                .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

            const SizedBox(height: 16),

            // DATA & STORAGE section
            TeacherSettingsSection(
              title: 'Data & Storage',
              items: [
                TeacherSettingsItem(
                  icon: Icons.cached,
                  iconBgColor: AppColors.teacherAccent,
                  label: 'Clear Cache',
                  onTap: _handleClearCache,
                ),
                TeacherSettingsItem(
                  icon: Icons.sync,
                  iconBgColor: AppColors.libraryGreen,
                  label: 'Sync Status',
                  trailing: _buildSyncStatusTrailing(),
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: 180.ms)
                .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

            const SizedBox(height: 16),

            // SUPPORT section
            TeacherSettingsSection(
              title: 'Support',
              items: [
                TeacherSettingsItem(
                  icon: Icons.feedback_outlined,
                  iconBgColor: AppColors.teacherPrimary,
                  label: 'Send Feedback',
                  onTap: () {
                    showFeedbackSheet(
                      context,
                      userId: widget.user.id,
                      userRole: 'teacher',
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.info_outline,
                  iconBgColor: AppColors.skyBlue,
                  label: 'About',
                  onTap: _showAboutDialog,
                ),
              ],
            )
                .animate()
                .fadeIn(duration: 300.ms, delay: 240.ms)
                .slideY(begin: 0.03, end: 0, curve: Curves.easeOut),

            const SizedBox(height: 24),

            // Log Out card
            _buildLogOutCard()
                .animate()
                .fadeIn(duration: 300.ms, delay: 300.ms),

            // Version footer
            _buildVersionFooter(),
          ],
        ),
      ),
    );
  }
}
