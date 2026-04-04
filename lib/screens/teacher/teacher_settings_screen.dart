import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/feedback_widget.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/offline_service.dart';

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
  // Persisted notification preferences (loaded from Firestore UserModel.preferences)
  late bool _pushNotificationsEnabled;
  late bool _inactivityAlerts;

  // Teacher's classes (for class picker navigation)
  List<ClassModel> _classes = [];
  bool _loadingClasses = true;

  @override
  void initState() {
    super.initState();
    final prefs = widget.user.preferences ?? {};
    _pushNotificationsEnabled = prefs['pushNotificationsEnabled'] ?? true;
    _inactivityAlerts = prefs['inactivityAlerts'] ?? true;
    _loadClasses();
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

  Future<void> _updatePreferences() async {
    final schoolId = widget.user.schoolId;
    if (schoolId == null) return;
    try {
      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('users')
          .doc(widget.user.id)
          .update({
        'preferences.pushNotificationsEnabled': _pushNotificationsEnabled,
        'preferences.inactivityAlerts': _inactivityAlerts,
      });
    } catch (e) {
      debugPrint('Error saving preferences: $e');
    }
  }

  Future<void> _togglePushNotifications(bool value) async {
    setState(() => _pushNotificationsEnabled = value);

    if (value) {
      // Request permission and register FCM token
      final granted = await NotificationService.instance.requestPermissions();
      if (!granted) {
        // Permission denied — revert toggle
        if (mounted) {
          setState(() => _pushNotificationsEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Notification permission denied. Enable in device settings.'),
            ),
          );
        }
        return;
      }
      final schoolId = widget.user.schoolId;
      if (schoolId != null) {
        await NotificationService.instance
            .saveTokenForUser(schoolId, widget.user.id);
      }
    } else {
      // Unregister FCM token
      await NotificationService.instance.clearTokenForUser();
    }

    await _updatePreferences();
  }

  Future<void> _toggleInactivityAlerts(bool value) async {
    setState(() => _inactivityAlerts = value);
    await _updatePreferences();
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

  Widget _buildToggle(bool value, ValueChanged<bool> onChanged) {
    return Switch(
      value: value,
      onChanged: onChanged,
      activeTrackColor: AppColors.teacherPrimary.withValues(alpha: 0.4),
      activeThumbColor: AppColors.teacherPrimary,
    );
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: TeacherTypography.h1),
            const SizedBox(height: 24),

            // CLASSROOM section
            TeacherSettingsSection(
              title: 'Classroom',
              items: [
                TeacherSettingsItem(
                  icon: Icons.auto_stories,
                  iconBgColor: AppColors.decodableBlue,
                  label: 'Reading Levels',
                  onTap: () => _navigateWithClass('/teacher/level-management'),
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
            ),

            const SizedBox(height: 16),

            // NOTIFICATIONS section
            TeacherSettingsSection(
              title: 'Notifications',
              items: [
                TeacherSettingsItem(
                  icon: Icons.notifications,
                  iconBgColor: AppColors.warmOrange,
                  label: 'Push Notifications',
                  trailing: _buildToggle(
                    _pushNotificationsEnabled,
                    _togglePushNotifications,
                  ),
                ),
                TeacherSettingsItem(
                  icon: Icons.warning_amber,
                  iconBgColor: AppColors.levelDigraphs,
                  label: 'Inactivity Alerts',
                  trailing: _buildToggle(
                    _inactivityAlerts,
                    _toggleInactivityAlerts,
                  ),
                ),
                TeacherSettingsItem(
                  icon: Icons.campaign,
                  iconBgColor: AppColors.skyBlue,
                  label: 'Notifications',
                  onTap: () {
                    context.push('/teacher/notifications',
                        extra: widget.user);
                  },
                ),
              ],
            ),

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
            ),

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
            ),

            const SizedBox(height: 24),

            // View Profile button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  context.push('/teacher/profile', extra: widget.user);
                },
                icon: const Icon(Icons.person),
                label: const Text('View Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teacherPrimary,
                  side: const BorderSide(color: AppColors.teacherPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                  textStyle: TeacherTypography.buttonText,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Log Out button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _handleSignOut,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Log Out',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
