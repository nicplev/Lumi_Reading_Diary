import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';

class ParentProfileScreen extends StatefulWidget {
  final UserModel user;

  const ParentProfileScreen({
    super.key,
    required this.user,
  });

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  bool _notificationsEnabled = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 19, minute: 0);
  bool _isLoading = false;
  List<StudentModel> _linkedChildren = [];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadLinkedChildren();
  }

  Future<void> _loadPreferences() async {
    // Load user preferences
    final preferences = widget.user.preferences;
    if (preferences != null) {
      setState(() {
        _notificationsEnabled = preferences['notificationsEnabled'] ?? true;
        if (preferences['reminderTime'] != null) {
          final timeString = preferences['reminderTime'];
          if (timeString.contains(':')) {
            final time = timeString.split(':');
            if (time.length >= 2) {
              _reminderTime = TimeOfDay(
                hour: int.tryParse(time[0]) ?? 20,
                minute: int.tryParse(time[1]) ?? 0,
              );
            }
          }
        }
      });
    }
  }

  Future<void> _loadLinkedChildren() async {
    final children = <StudentModel>[];
    for (String childId in widget.user.linkedChildren) {
      final doc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .doc(childId)
          .get();
      if (doc.exists) {
        children.add(StudentModel.fromFirestore(doc));
      }
    }
    setState(() {
      _linkedChildren = children;
    });
  }

  Future<void> _updatePreferences() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('parents')
          .doc(widget.user.id)
          .update({
        'preferences': {
          'notificationsEnabled': _notificationsEnabled,
          'reminderTime': '${_reminderTime.hour}:${_reminderTime.minute}',
        },
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferences updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) {
        context.go('/auth/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.primaryBlue,
                    child: Text(
                      widget.user.fullName.isNotEmpty
                          ? widget.user.fullName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 36,
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.user.fullName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.user.email,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.parentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Parent',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.parentColor,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Linked Children Section
            _buildSectionTitle(
                context, 'Linked Children', Icons.family_restroom),
            Container(
              color: AppColors.white,
              child: _linkedChildren.isEmpty
                  ? ListTile(
                      leading:
                          const Icon(Icons.info_outline, color: AppColors.gray),
                      title: Text(
                        'No children linked',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.gray,
                            ),
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          // Navigate to add child
                        },
                        child: const Text('Add Child'),
                      ),
                    )
                  : Column(
                      children: _linkedChildren.map((child) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primaryBlue.withOpacity(0.1),
                            child: Text(
                              child.firstName.isNotEmpty
                                  ? child.firstName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: AppColors.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(child.fullName),
                          subtitle: Text(
                            'Level: ${child.currentReadingLevel ?? "Not set"}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.gray,
                                    ),
                          ),
                          trailing: StreamBuilder<DocumentSnapshot>(
                            stream: _firebaseService.firestore
                                .collection('schools')
                                .doc(widget.user.schoolId)
                                .collection('students')
                                .doc(child.id)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const SizedBox();
                              final data = snapshot.data!.data()
                                  as Map<String, dynamic>?;
                              final stats =
                                  data?['stats'] as Map<String, dynamic>?;
                              final streak = stats?['currentStreak'] ?? 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.secondaryOrange
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department,
                                      size: 16,
                                      color: AppColors.secondaryOrange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$streak',
                                      style: TextStyle(
                                        color: AppColors.secondaryOrange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),
            ),

            const SizedBox(height: 16),

            // Notification Settings
            _buildSectionTitle(
                context, 'Notifications', Icons.notifications_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Daily Reminders'),
                    subtitle: const Text('Get reminded to log daily reading'),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                      _updatePreferences();
                    },
                    activeThumbColor: AppColors.primaryBlue,
                  ),
                  if (_notificationsEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('Reminder Time'),
                      subtitle: Text(
                        _reminderTime.format(context),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.primaryBlue,
                            ),
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final TimeOfDay? picked = await showTimePicker(
                          context: context,
                          initialTime: _reminderTime,
                        );
                        if (picked != null && picked != _reminderTime) {
                          setState(() {
                            _reminderTime = picked;
                          });
                          _updatePreferences();
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // App Settings
            _buildSectionTitle(context, 'Settings', Icons.settings_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: const Text('Language'),
                    subtitle: const Text('English'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to language settings
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Help & Support'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to help
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to privacy policy
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('About Lumi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showAboutDialog();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Actions
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.qr_code_scanner,
                        color: AppColors.primaryBlue),
                    title: Text(
                      'Enter Invite Code',
                      style: TextStyle(color: AppColors.primaryBlue),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.primaryBlue),
                    onTap: () {
                      // Navigate to enter invite code
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: Text(
                      'Sign Out',
                      style: TextStyle(color: AppColors.error),
                    ),
                    onTap: _handleSignOut,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Version info
            Text(
              'Version 1.0.0',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray,
                  ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.gray),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGray,
                ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumiMascot(
                mood: LumiMood.happy,
                size: 100,
              ),
              const SizedBox(height: 16),
              Text(
                'Lumi Reading Diary',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Version 1.0.0',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Making reading fun and trackable for every child. Lumi helps families build consistent reading habits together.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
