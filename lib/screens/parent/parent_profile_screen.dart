import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
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
        shape: LumiBorders.shapeLarge,
        title: Text('Sign Out', style: LumiTextStyles.h3()),
        content: Text(
          'Are you sure you want to sign out?',
          style: LumiTextStyles.body(),
        ),
        actions: [
          LumiTextButton(
            onPressed: () => Navigator.pop(context, false),
            text: 'Cancel',
          ),
          LumiTextButton(
            onPressed: () => Navigator.pop(context, true),
            text: 'Sign Out',
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
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Profile', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header
            Container(
              color: AppColors.white,
              padding: LumiPadding.allM,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.rosePink,
                    child: Text(
                      widget.user.fullName.isNotEmpty
                          ? widget.user.fullName[0].toUpperCase()
                          : '?',
                      style: LumiTextStyles.display(color: AppColors.white),
                    ),
                  ),
                  LumiGap.s,
                  Text(
                    widget.user.fullName,
                    style: LumiTextStyles.h2(),
                  ),
                  LumiGap.xxs,
                  Text(
                    widget.user.email,
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withOpacity(0.7),
                    ),
                  ),
                  LumiGap.xs,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumiSpacing.inputPaddingVertical,
                      vertical: LumiSpacing.elementSpacing - 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rosePink.withOpacity(0.1),
                      borderRadius: LumiBorders.circular,
                    ),
                    child: Text(
                      'Parent',
                      style: LumiTextStyles.label(color: AppColors.rosePink),
                    ),
                  ),
                ],
              ),
            ),

            LumiGap.s,

            // Linked Children Section
            _buildSectionTitle(
                context, 'Linked Children', Icons.family_restroom),
            Container(
              color: AppColors.white,
              child: _linkedChildren.isEmpty
                  ? ListTile(
                      leading: Icon(Icons.info_outline,
                          color: AppColors.charcoal.withOpacity(0.5)),
                      title: Text(
                        'No children linked',
                        style: LumiTextStyles.body(
                          color: AppColors.charcoal.withOpacity(0.7),
                        ),
                      ),
                      trailing: LumiTextButton(
                        onPressed: () {
                          // Navigate to add child
                        },
                        text: 'Add Child',
                      ),
                    )
                  : Column(
                      children: _linkedChildren.map((child) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.rosePink.withOpacity(0.1),
                            child: Text(
                              child.firstName.isNotEmpty
                                  ? child.firstName[0].toUpperCase()
                                  : '?',
                              style: LumiTextStyles.bodyMedium(
                                color: AppColors.rosePink,
                              ),
                            ),
                          ),
                          title: Text(child.fullName, style: LumiTextStyles.bodyMedium()),
                          subtitle: Text(
                            'Level: ${child.currentReadingLevel ?? "Not set"}',
                            style: LumiTextStyles.bodySmall(
                              color: AppColors.charcoal.withOpacity(0.7),
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
                                  horizontal: LumiSpacing.xs,
                                  vertical: LumiSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warmOrange.withOpacity(0.1),
                                  borderRadius: LumiBorders.medium,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department,
                                      size: 16,
                                      color: AppColors.warmOrange,
                                    ),
                                    LumiGap.horizontalXXS,
                                    Text(
                                      '$streak',
                                      style: LumiTextStyles.label(
                                        color: AppColors.warmOrange,
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

            LumiGap.s,

            // Notification Settings
            _buildSectionTitle(
                context, 'Notifications', Icons.notifications_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('Daily Reminders', style: LumiTextStyles.bodyMedium()),
                    subtitle: Text('Get reminded to log daily reading', style: LumiTextStyles.bodySmall()),
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                      _updatePreferences();
                    },
                    activeColor: AppColors.rosePink,
                  ),
                  if (_notificationsEnabled) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text('Reminder Time', style: LumiTextStyles.bodyMedium()),
                      subtitle: Text(
                        _reminderTime.format(context),
                        style: LumiTextStyles.bodySmall(color: AppColors.rosePink),
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

            LumiGap.s,

            // App Settings
            _buildSectionTitle(context, 'Settings', Icons.settings_outlined),
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text('Language', style: LumiTextStyles.bodyMedium()),
                    subtitle: Text('English', style: LumiTextStyles.bodySmall()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to language settings
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text('Help & Support', style: LumiTextStyles.bodyMedium()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to help
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: Text('Privacy Policy', style: LumiTextStyles.bodyMedium()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // Navigate to privacy policy
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text('About Lumi', style: LumiTextStyles.bodyMedium()),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _showAboutDialog();
                    },
                  ),
                ],
              ),
            ),

            LumiGap.s,

            // Actions
            Container(
              color: AppColors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.qr_code_scanner,
                        color: AppColors.rosePink),
                    title: Text(
                      'Enter Invite Code',
                      style: LumiTextStyles.bodyMedium(color: AppColors.rosePink),
                    ),
                    trailing: const Icon(Icons.chevron_right,
                        color: AppColors.rosePink),
                    onTap: () {
                      // Navigate to enter invite code
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: Text(
                      'Sign Out',
                      style: LumiTextStyles.bodyMedium(color: AppColors.error),
                    ),
                    onTap: _handleSignOut,
                  ),
                ],
              ),
            ),

            LumiGap.l,

            // Version info
            Text(
              'Version 1.0.0',
              style: LumiTextStyles.caption(),
            ),

            LumiGap.s,
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        LumiSpacing.s,
        LumiSpacing.s,
        LumiSpacing.s,
        LumiSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.charcoal.withOpacity(0.7)),
          LumiGap.horizontalXS,
          Text(
            title,
            style: LumiTextStyles.h3(),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: LumiBorders.shapeLarge,
        child: Container(
          padding: LumiPadding.allM,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumiMascot(
                mood: LumiMood.happy,
                size: 100,
              ),
              LumiGap.s,
              Text(
                'Lumi Reading Diary',
                style: LumiTextStyles.h2(),
              ),
              LumiGap.xs,
              Text(
                'Version 1.0.0',
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal.withOpacity(0.7),
                ),
              ),
              LumiGap.s,
              Text(
                'Making reading fun and trackable for every child. Lumi helps families build consistent reading habits together.',
                textAlign: TextAlign.center,
                style: LumiTextStyles.body(),
              ),
              LumiGap.m,
              LumiTextButton(
                onPressed: () => Navigator.pop(context),
                text: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
