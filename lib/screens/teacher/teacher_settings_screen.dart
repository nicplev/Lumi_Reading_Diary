import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';

/// Teacher Settings Screen (Tab 4)
///
/// Grouped settings sections with profile access and sign out.
/// Per spec: 3 sections (Classroom, Notifications, App) + Profile + Log Out.
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
  bool _pushNotifications = true;
  bool _emailSummaries = true;
  bool _inactivityAlerts = true;
  bool _darkMode = false;

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
            child: Text(
              'Cancel',
              style: TeacherTypography.buttonText.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Sign Out',
              style: TeacherTypography.buttonText.copyWith(
                color: AppColors.error,
              ),
            ),
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
                  icon: Icons.school,
                  iconBgColor: AppColors.teacherPrimary,
                  label: 'Manage Classes',
                  onTap: () {
                    // Navigate to class management
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to class management')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.people,
                  iconBgColor: AppColors.teacherAccent,
                  label: 'Student Management',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Navigate to student management')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.menu_book,
                  iconBgColor: AppColors.decodableBlue,
                  label: 'Book Levels',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Book Levels coming soon')),
                    );
                  },
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
                    _pushNotifications,
                    (v) => setState(() => _pushNotifications = v),
                  ),
                ),
                TeacherSettingsItem(
                  icon: Icons.email,
                  iconBgColor: AppColors.skyBlue,
                  label: 'Email Summaries',
                  trailing: _buildToggle(
                    _emailSummaries,
                    (v) => setState(() => _emailSummaries = v),
                  ),
                ),
                TeacherSettingsItem(
                  icon: Icons.warning_amber,
                  iconBgColor: const Color(0xFFFFCC80),
                  label: 'Inactivity Alerts',
                  trailing: _buildToggle(
                    _inactivityAlerts,
                    (v) => setState(() => _inactivityAlerts = v),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // APP section
            TeacherSettingsSection(
              title: 'App',
              items: [
                TeacherSettingsItem(
                  icon: Icons.dark_mode,
                  iconBgColor: const Color(0xFF37474F),
                  label: 'Dark Mode',
                  trailing: _buildToggle(
                    _darkMode,
                    (v) => setState(() => _darkMode = v),
                  ),
                ),
                TeacherSettingsItem(
                  icon: Icons.lock,
                  iconBgColor: AppColors.teacherPrimary,
                  label: 'Privacy & Security',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Privacy & Security coming soon')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.help,
                  iconBgColor: const Color(0xFF81C784),
                  label: 'Help & Support',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Help & Support coming soon')),
                    );
                  },
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
                    borderRadius: BorderRadius.circular(14),
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
