import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import 'widgets/character_picker_sheet.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../core/widgets/lumi/feedback_widget.dart';

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
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _settingsKey = GlobalKey();
  bool _notificationsEnabled = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 19, minute: 0);
  // Selected weekdays (1=Mon..7=Sun). Empty = every day.
  List<int> _reminderDays = [];
  bool _isLoading = false;
  List<StudentModel> _linkedChildren = [];
  bool _settingsExpanded = false;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayValues = [1, 2, 3, 4, 5, 6, 7]; // DateTime weekdays

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadLinkedChildren();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final preferences = widget.user.preferences;
    if (preferences != null) {
      setState(() {
        _notificationsEnabled = preferences['notificationsEnabled'] ?? true;
        if (preferences['reminderTime'] != null) {
          final timeString = preferences['reminderTime'] as String;
          if (timeString.contains(':')) {
            final parts = timeString.split(':');
            if (parts.length >= 2) {
              _reminderTime = TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 19,
                minute: int.tryParse(parts[1]) ?? 0,
              );
            }
          }
        }
        // Load selected days (empty = every day)
        if (preferences['reminderDays'] != null) {
          _reminderDays = List<int>.from(preferences['reminderDays']);
        }
      });
    }

    // Sync local notifications after children are loaded
    // (called again from _loadLinkedChildren once children are available)
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

    // Now that children are loaded, sync local notification state
    await _syncLocalNotifications();
  }

  /// Schedule or cancel local notifications based on current preferences.
  Future<void> _syncLocalNotifications() async {
    if (_notificationsEnabled && _linkedChildren.isNotEmpty) {
      await NotificationService.instance.scheduleReminders(
        childNames: _linkedChildren.map((c) => c.firstName).toList(),
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        days: _reminderDays.isEmpty ? null : _reminderDays,
      );
    } else {
      await NotificationService.instance.cancelAllReminders();
    }
  }

  Future<void> _updatePreferences() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Save to Firestore (including reminder days)
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('parents')
          .doc(widget.user.id)
          .update({
        'preferences': {
          'notificationsEnabled': _notificationsEnabled,
          'reminderTime': '${_reminderTime.hour}:${_reminderTime.minute}',
          'reminderDays': _reminderDays, // [] = every day
        },
      });

      // Sync local notifications
      await _syncLocalNotifications();

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

  void _scrollToSettings() {
    setState(() {
      _settingsExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _settingsKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: LumiPadding.allS,
          child: Column(
            children: [
              _buildProfileHeader(),
              LumiGap.m,
              _buildLinkedChildrenCard(),
              LumiGap.m,
              _buildNotificationsCard(),
              LumiGap.m,
              _buildInviteCodeCard(),
              LumiGap.m,
              _buildSettingsCard(),
              LumiGap.m,
              LumiTextButton(
                onPressed: _handleSignOut,
                text: 'Sign Out',
                color: AppColors.charcoal.withValues(alpha: 0.5),
              ),
              LumiGap.xs,
              Text(
                'Version 1.0.0',
                style: LumiTextStyles.caption(),
              ),
              LumiGap.l,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    // Compute aggregate streak from linked children
    final childCount = _linkedChildren.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: LumiBorders.large,
        boxShadow: [
          BoxShadow(
            color: AppColors.rosePink.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LumiSpacing.m,
              LumiSpacing.m,
              LumiSpacing.m,
              LumiSpacing.m,
            ),
            child: Column(
              children: [
                const LumiMascot(variant: LumiVariant.welcome, size: 80),
                LumiGap.s,
                Text(
                  widget.user.fullName,
                  style: LumiTextStyles.h2(color: AppColors.white),
                ),
                LumiGap.xxs,
                Text(
                  widget.user.email,
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.white.withValues(alpha: 0.85),
                  ),
                ),
                LumiGap.s,
                // Stat chips row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildStatChip(
                      Icons.people_outline,
                      '$childCount ${childCount == 1 ? 'child' : 'children'}',
                    ),
                    LumiGap.horizontalS,
                    // Aggregate streak chip
                    StreamBuilder<List<DocumentSnapshot>>(
                      stream: _linkedChildren.isNotEmpty
                          ? _buildAggregateStreakStream()
                          : const Stream.empty(),
                      builder: (context, snapshot) {
                        int totalStreak = 0;
                        if (snapshot.hasData) {
                          for (final doc in snapshot.data!) {
                            final data =
                                doc.data() as Map<String, dynamic>?;
                            final stats =
                                data?['stats'] as Map<String, dynamic>?;
                            totalStreak +=
                                (stats?['currentStreak'] ?? 0) as int;
                          }
                        }
                        return _buildStatChip(
                          Icons.local_fire_department,
                          '$totalStreak day streak',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Settings gear icon at top-right
          Positioned(
            top: LumiSpacing.xs,
            right: LumiSpacing.xs,
            child: LumiIconButton(
              onPressed: _scrollToSettings,
              icon: Icons.settings_outlined,
              iconColor: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }

  Stream<List<DocumentSnapshot>> _buildAggregateStreakStream() {
    final streams = _linkedChildren.map((child) {
      return _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .doc(child.id)
          .snapshots();
    }).toList();

    return streams.first.asyncExpand((firstDoc) {
      if (streams.length == 1) {
        return Stream.value([firstDoc]);
      }
      // Combine all streams
      return _combineStreams(streams);
    });
  }

  Stream<List<DocumentSnapshot>> _combineStreams(
      List<Stream<DocumentSnapshot>> streams) {
    final latest = List<DocumentSnapshot?>.filled(streams.length, null);
    return Stream.multi((controller) {
      for (int i = 0; i < streams.length; i++) {
        final index = i;
        streams[index].listen(
          (doc) {
            latest[index] = doc;
            if (latest.every((d) => d != null)) {
              controller.add(latest.cast<DocumentSnapshot>());
            }
          },
          onError: controller.addError,
        );
      }
    });
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiSpacing.xs + 4,
        vertical: LumiSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.2),
        borderRadius: LumiBorders.circular,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.white),
          LumiGap.horizontalXXS,
          Text(
            label,
            style: LumiTextStyles.label(color: AppColors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedChildrenCard() {
    if (_linkedChildren.isEmpty) {
      return LumiEmptyCard(
        icon: Icons.family_restroom,
        title: 'No children linked',
        message: 'Link a child to start tracking their reading progress.',
        actionText: 'Add Child',
        onAction: () {
          // Navigate to add child
        },
      );
    }

    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title inside the card
          Row(
            children: [
              Icon(Icons.family_restroom,
                  size: 20,
                  color: AppColors.charcoal.withValues(alpha: 0.7)),
              LumiGap.horizontalXS,
              Text('Your Children', style: LumiTextStyles.h3()),
            ],
          ),
          LumiGap.s,
          // Child rows
          ..._linkedChildren.map((child) {
            return Padding(
              padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
              child: Container(
                padding: const EdgeInsets.all(LumiSpacing.xs + 4),
                decoration: BoxDecoration(
                  color: AppColors.offWhite,
                  borderRadius: LumiBorders.medium,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => showCharacterPicker(
                        context,
                        student: child,
                        schoolId: widget.user.schoolId ?? '',
                        onChanged: (updated) {
                          setState(() {
                            final idx = _linkedChildren.indexWhere((c) => c.id == updated.id);
                            if (idx != -1) _linkedChildren[idx] = updated;
                          });
                        },
                      ),
                      child: Stack(
                        children: [
                          StudentAvatar.fromStudent(child, size: 40),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.rosePink,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(Icons.edit, size: 9, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    LumiGap.horizontalS,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(child.fullName,
                              style: LumiTextStyles.bodyMedium()),
                          Text(
                            'Level: ${child.currentReadingLevel ?? "Not set"}',
                            style: LumiTextStyles.bodySmall(
                              color:
                                  AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StreamBuilder<DocumentSnapshot>(
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
                            color:
                                AppColors.warmOrange.withValues(alpha: 0.1),
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
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard() {
    return LumiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Icon(Icons.notifications_outlined,
                  size: 20,
                  color: AppColors.charcoal.withValues(alpha: 0.7)),
              LumiGap.horizontalXS,
              Text('Reminders', style: LumiTextStyles.h3()),
              const Spacer(),
              Switch.adaptive(
                value: _notificationsEnabled,
                onChanged: (value) {
                  setState(() {
                    _notificationsEnabled = value;
                  });
                  _updatePreferences();
                },
                activeTrackColor: AppColors.rosePink,
              ),
            ],
          ),
          // Content when enabled or disabled
          AnimatedCrossFade(
            firstChild: _buildNotificationDetails(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: LumiSpacing.xs),
              child: Text(
                'Reminders are off',
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
              ),
            ),
            crossFadeState: _notificationsEnabled
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationDetails() {
    return Padding(
      padding: const EdgeInsets.only(top: LumiSpacing.s),
      child: Container(
        padding: const EdgeInsets.all(LumiSpacing.s),
        decoration: BoxDecoration(
          color: AppColors.rosePink.withValues(alpha: 0.06),
          borderRadius: LumiBorders.medium,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time row
            Row(
              children: [
                Icon(Icons.access_time,
                    size: 18,
                    color: AppColors.charcoal.withValues(alpha: 0.7)),
                LumiGap.horizontalXS,
                Text('Remind me at', style: LumiTextStyles.bodySmall()),
                LumiGap.horizontalXS,
                GestureDetector(
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumiSpacing.xs + 4,
                      vertical: LumiSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.rosePink,
                      borderRadius: LumiBorders.circular,
                    ),
                    child: Text(
                      _reminderTime.format(context),
                      style: LumiTextStyles.label(color: AppColors.white),
                    ),
                  ),
                ),
              ],
            ),
            LumiGap.s,
            // Day chips row
            Text(
              _reminderDays.isEmpty ? 'On these days (every day)' : 'On these days',
              style: LumiTextStyles.bodySmall(),
            ),
            LumiGap.xs,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                final day = _dayValues[index];
                final isSelected =
                    _reminderDays.isEmpty || _reminderDays.contains(day);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_reminderDays.isEmpty) {
                        _reminderDays = List.from(_dayValues);
                        _reminderDays.remove(day);
                      } else if (_reminderDays.contains(day)) {
                        _reminderDays.remove(day);
                        if (_reminderDays.isEmpty) {
                          _reminderDays = [];
                        }
                      } else {
                        _reminderDays.add(day);
                        _reminderDays.sort();
                        if (_reminderDays.length == 7) {
                          _reminderDays = [];
                        }
                      }
                    });
                    _updatePreferences();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.rosePink
                          : AppColors.rosePink.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _dayLabels[index],
                      style: LumiTextStyles.label(
                        color: isSelected
                            ? AppColors.white
                            : AppColors.rosePink,
                      ),
                    ),
                  ),
                );
              }),
            ),
            LumiGap.s,
            // Reminder preview
            _buildReminderPreview(),
            LumiGap.xs,
            // Test notification button
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => NotificationService.instance.testNotification(),
                icon: Icon(
                  Icons.send_outlined,
                  size: 16,
                  color: AppColors.charcoal.withValues(alpha: 0.5),
                ),
                label: Text(
                  'Send test',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.5),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LumiSpacing.xs,
                    vertical: LumiSpacing.xxs,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderPreview() {
    final String exampleName;
    final String suffix;
    if (_linkedChildren.isEmpty) {
      exampleName = 'your child';
      suffix = '';
    } else if (_linkedChildren.length == 1) {
      exampleName = _linkedChildren.first.firstName;
      suffix = '';
    } else {
      exampleName = _linkedChildren.first.firstName;
      suffix = ' (and ${_linkedChildren.length - 1} more)';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiSpacing.s,
        vertical: LumiSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.charcoal.withValues(alpha: 0.04),
        borderRadius: LumiBorders.medium,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_active_outlined,
            size: 15,
            color: AppColors.charcoal.withValues(alpha: 0.4),
          ),
          LumiGap.horizontalXXS,
          Expanded(
            child: Text(
              '"Don\'t forget to log $exampleName\'s reading today!"$suffix',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.55),
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCodeCard() {
    return LumiCard(
      onTap: () {
        // Navigate to enter invite code
      },
      child: Row(
        children: [
          Icon(Icons.qr_code_scanner, color: AppColors.rosePink, size: 24),
          LumiGap.horizontalS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter Invite Code',
                  style: LumiTextStyles.bodyMedium(color: AppColors.rosePink),
                ),
                Text(
                  'Link a new child to your account',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: AppColors.rosePink,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return LumiCard(
      key: _settingsKey,
      child: Column(
        children: [
          // Header row — always visible
          GestureDetector(
            onTap: () {
              setState(() {
                _settingsExpanded = !_settingsExpanded;
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.settings_outlined,
                    size: 20,
                    color: AppColors.charcoal.withValues(alpha: 0.7)),
                LumiGap.horizontalXS,
                Text('Settings', style: LumiTextStyles.h3()),
                const Spacer(),
                AnimatedRotation(
                  turns: _settingsExpanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.expand_more),
                ),
              ],
            ),
          ),
          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: LumiSpacing.s),
              child: Column(
                children: [
                  _buildSettingsRow(
                    Icons.language,
                    'Language',
                    subtitle: 'English',
                    onTap: () {
                      // Navigate to language settings
                    },
                  ),
                  _buildSettingsRow(
                    Icons.help_outline,
                    'Help & Support',
                    onTap: () {
                      // Navigate to help
                    },
                  ),
                  _buildSettingsRow(
                    Icons.feedback_outlined,
                    'Send Feedback',
                    color: AppColors.rosePink,
                    onTap: () {
                      showFeedbackSheet(
                        context,
                        userId: widget.user.id,
                        userRole: widget.user.role.name,
                      );
                    },
                  ),
                  _buildSettingsRow(
                    Icons.privacy_tip_outlined,
                    'Privacy Policy',
                    onTap: () {
                      // Navigate to privacy policy
                    },
                  ),
                  _buildSettingsRow(
                    Icons.info_outline,
                    'About Lumi',
                    onTap: _showAboutDialog,
                    showDivider: false,
                  ),
                ],
              ),
            ),
            crossFadeState: _settingsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(
    IconData icon,
    String title, {
    String? subtitle,
    Color? color,
    VoidCallback? onTap,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LumiSpacing.xs + 2),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color ?? AppColors.charcoal.withValues(alpha: 0.7)),
                LumiGap.horizontalS,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: LumiTextStyles.bodyMedium(color: color),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: LumiTextStyles.bodySmall(
                            color: AppColors.charcoal.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: color ?? AppColors.charcoal.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            color: AppColors.charcoal.withValues(alpha: 0.06),
          ),
      ],
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
                variant: LumiVariant.parent,
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
                  color: AppColors.charcoal.withValues(alpha: 0.7),
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
