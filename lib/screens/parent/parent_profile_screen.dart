import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/student_avatar.dart';
import '../../core/widgets/lumi/feedback_widget.dart';
import '../../core/widgets/lumi/legal_links_row.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/providers/active_child_provider.dart';
import '../../core/services/service_status_controller.dart';
import '../../services/firebase_service.dart';
import '../../services/notification_service.dart';
import '../../services/offline_service.dart';
import 'widgets/add_email_for_recovery_modal.dart';
import 'settings/child_manage_sheet.dart';

/// Vertical space the floating glass nav occupies; scroll content reserves this
/// so the last item clears the bar (mirrors Home/Library).
const double _kNavClearance = 92;

class ParentProfileScreen extends ConsumerStatefulWidget {
  final UserModel user;

  const ParentProfileScreen({super.key, required this.user});

  @override
  ConsumerState<ParentProfileScreen> createState() =>
      _ParentProfileScreenState();
}

class _ParentProfileScreenState extends ConsumerState<ParentProfileScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;

  bool _notificationsEnabled = true;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 19, minute: 0);
  // Selected weekdays (1=Mon..7=Sun). Empty = every day.
  List<int> _reminderDays = [];
  List<StudentModel> _linkedChildren = [];
  // Local copy of the parent's relationship label so edits reflect immediately
  // without needing the upstream UserModel to refresh.
  String? _relationshipLabel;

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayValues = [1, 2, 3, 4, 5, 6, 7]; // DateTime weekdays

  @override
  void initState() {
    super.initState();
    _relationshipLabel = widget.user.relationshipLabel;
    _linkedChildren =
        ref.read(parentChildrenProvider).value ?? const <StudentModel>[];
    _loadPreferences();
  }

  void _loadPreferences() {
    final preferences = widget.user.preferences;
    if (preferences == null) return;
    setState(() {
      _notificationsEnabled = preferences['notificationsEnabled'] ?? true;
      final timeString = preferences['reminderTime'] as String?;
      if (timeString != null && timeString.contains(':')) {
        final parts = timeString.split(':');
        if (parts.length >= 2) {
          _reminderTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 19,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
      if (preferences['reminderDays'] != null) {
        _reminderDays = List<int>.from(preferences['reminderDays']);
      }
    });
  }

  Future<void> _updatePreferences() async {
    final prefs = <String, dynamic>{
      'notificationsEnabled': _notificationsEnabled,
      'reminderTime': '${_reminderTime.hour}:${_reminderTime.minute}',
      'reminderDays': _reminderDays, // [] = every day
    };
    final schoolId = widget.user.schoolId;

    try {
      if (ServiceStatusController.instance.current.canWriteToFirebase) {
        await _firebaseService.firestore
            .collection('schools')
            .doc(schoolId)
            .collection('parents')
            .doc(widget.user.id)
            .update({'preferences': prefs});
      } else if (schoolId != null) {
        await OfflineService.instance.enqueueParentPrefs(
          parentId: widget.user.id,
          schoolId: schoolId,
          preferences: prefs,
        );
      }
      if (mounted) {
        final queued =
            !ServiceStatusController.instance.current.canWriteToFirebase;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(queued
                ? 'Saved — will sync when reconnected'
                : 'Preferences updated'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update preferences')),
        );
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Sign out', style: LumiType.subhead),
        content: Text('Are you sure you want to sign out?',
            style: LumiType.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: LumiType.body.copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign out',
                style: LumiType.body
                    .copyWith(color: LumiTokens.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) context.go('/auth/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the local children list in sync with the live provider.
    ref.listen<AsyncValue<List<StudentModel>>>(
      parentChildrenProvider,
      (_, next) {
        final children = next.value;
        if (children == null || !mounted) return;
        final sameSet = children.length == _linkedChildren.length &&
            children.every(
              (c) => _linkedChildren.any((existing) => existing.id == c.id),
            );
        if (!sameSet) setState(() => _linkedChildren = children);
      },
    );

    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LumiTokens.space4,
            LumiTokens.space2,
            LumiTokens.space4,
            _kNavClearance,
          ),
          children: [
            _buildHeader(),
            const SizedBox(height: LumiTokens.space6),
            _buildYouSection(),
            const SizedBox(height: LumiTokens.space5),
            _buildChildrenSection(),
            const SizedBox(height: LumiTokens.space5),
            _buildRemindersCard(),
            const SizedBox(height: LumiTokens.space5),
            _buildAboutSection(),
            const SizedBox(height: LumiTokens.space5),
            _buildSignOut(),
            const SizedBox(height: LumiTokens.space3),
            Center(
              child: Text('Version 1.0.0', style: LumiType.caption),
            ),
          ],
        ),
      ),
    );
  }

  // ── Compact header ──

  Widget _buildHeader() {
    final childCount = _linkedChildren.length;
    return Padding(
      padding: const EdgeInsets.only(top: LumiTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: LumiType.heading),
          const SizedBox(height: LumiTokens.space4),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: LumiTokens.tintGreen,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: const LumiMascot(variant: LumiVariant.parent, size: 48),
              ),
              const SizedBox(width: LumiTokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.fullName,
                      style: LumiType.subhead,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.user.contactIdentifier,
                      style: LumiType.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: LumiTokens.space2),
                    _HeaderChip(
                      icon: Icons.people_outline,
                      label:
                          '$childCount ${childCount == 1 ? 'child' : 'children'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── "You" ──

  Widget _buildYouSection() {
    final label = _relationshipLabel;
    return _Section(
      title: 'You',
      child: _SettingsGroup(
        rows: [
          _SettingsRow(
            icon: Icons.diversity_1_outlined,
            title: 'Relationship',
            value: label == null || label.isEmpty ? 'Set' : label,
            onTap: _editRelationship,
          ),
          if ((widget.user.email ?? '').isEmpty)
            _SettingsRow(
              icon: Icons.shield_outlined,
              title: 'Add recovery email',
              subtitle: 'Get back in if you lose your phone',
              onTap: () => AddEmailForRecoveryModal.show(
                context: context,
                user: widget.user,
              ),
            ),
        ],
      ),
    );
  }

  // ── "Children" ──

  Widget _buildChildrenSection() {
    return _Section(
      title: 'Children',
      child: _SettingsGroup(
        rows: [
          ..._linkedChildren.map(_buildChildRow),
          _SettingsRow(
            icon: Icons.qr_code_scanner,
            title: 'Link a new child',
            subtitle: 'Enter an invite code',
            accent: true,
            onTap: () => context.push('/parent/link-child'),
          ),
        ],
      ),
    );
  }

  Widget _buildChildRow(StudentModel child) {
    return InkWell(
      onTap: () => showChildManageSheet(
        context,
        user: widget.user,
        child: child,
        onChanged: (updated) {
          setState(() {
            final idx = _linkedChildren.indexWhere((c) => c.id == updated.id);
            if (idx != -1) _linkedChildren[idx] = updated;
          });
          ref.invalidate(parentChildrenProvider);
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space4),
        child: Row(
          children: [
            StudentAvatar.fromStudent(child, size: 40),
            const SizedBox(width: LumiTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.fullName,
                    style: LumiType.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    'Level: ${child.currentReadingLevel ?? 'Not set'}',
                    style: LumiType.caption,
                  ),
                ],
              ),
            ),
            _buildChildStreakBadge(child),
            const SizedBox(width: LumiTokens.space2),
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: LumiTokens.muted),
          ],
        ),
      ),
    );
  }

  Widget _buildChildStreakBadge(StudentModel child) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('students')
          .doc(child.id)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final stats = data?['stats'] as Map<String, dynamic>?;
        final streak = (stats?['currentStreak'] ?? 0) as int;
        if (streak <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: LumiTokens.space2,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: LumiTokens.tintOrange,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department,
                  size: 14, color: LumiTokens.orange),
              const SizedBox(width: 3),
              Text(
                '$streak',
                style: LumiType.caption.copyWith(
                  fontWeight: FontWeight.w700,
                  color: LumiTokens.ink,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Reminders ──

  Widget _buildRemindersCard() {
    return _Section(
      title: 'Reminders',
      child: Container(
        padding: const EdgeInsets.all(LumiTokens.space4),
        decoration: BoxDecoration(
          color: LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          boxShadow: LumiTokens.shadowCard,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    size: 20, color: LumiTokens.green),
                const SizedBox(width: LumiTokens.space3),
                Expanded(
                  child: Text(
                    'Reading reminders',
                    style:
                        LumiType.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Switch.adaptive(
                  value: _notificationsEnabled,
                  activeTrackColor: LumiTokens.green,
                  onChanged: (value) {
                    setState(() => _notificationsEnabled = value);
                    _updatePreferences();
                  },
                ),
              ],
            ),
            if (_notificationsEnabled)
              _buildReminderDetails()
            else
              Padding(
                padding: const EdgeInsets.only(top: LumiTokens.space2),
                child: Text('Reminders are off', style: LumiType.caption),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderDetails() {
    return Padding(
      padding: const EdgeInsets.only(top: LumiTokens.space3),
      child: Container(
        padding: const EdgeInsets.all(LumiTokens.space4),
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time row.
            Row(
              children: [
                const Icon(Icons.access_time,
                    size: 18, color: LumiTokens.muted),
                const SizedBox(width: LumiTokens.space2),
                Text('Remind me at', style: LumiType.body),
                const SizedBox(width: LumiTokens.space3),
                GestureDetector(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _reminderTime,
                    );
                    if (picked != null && picked != _reminderTime) {
                      setState(() => _reminderTime = picked);
                      _updatePreferences();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumiTokens.space3,
                      vertical: LumiTokens.space1,
                    ),
                    decoration: BoxDecoration(
                      color: LumiTokens.green,
                      borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
                    ),
                    child: Text(
                      _reminderTime.format(context),
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.paper,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LumiTokens.space4),
            Text(
              _reminderDays.isEmpty ? 'On these days (every day)' : 'On these days',
              style: LumiType.caption,
            ),
            const SizedBox(height: LumiTokens.space2),
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
                        _reminderDays = List.from(_dayValues)..remove(day);
                      } else if (_reminderDays.contains(day)) {
                        _reminderDays.remove(day);
                      } else {
                        _reminderDays.add(day);
                        _reminderDays.sort();
                        if (_reminderDays.length == 7) _reminderDays = [];
                      }
                    });
                    _updatePreferences();
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? LumiTokens.green : LumiTokens.tintGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _dayLabels[index],
                      style: LumiType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isSelected ? LumiTokens.paper : LumiTokens.ink,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: LumiTokens.space4),
            _buildReminderPreview(),
            const SizedBox(height: LumiTokens.space2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => NotificationService.instance.testNotification(),
                icon: const Icon(Icons.send_outlined,
                    size: 16, color: LumiTokens.muted),
                label: Text('Send test',
                    style: LumiType.caption.copyWith(color: LumiTokens.muted)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: LumiTokens.space2,
                    vertical: 2,
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
        horizontal: LumiTokens.space3,
        vertical: LumiTokens.space3,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.notifications_active_outlined,
              size: 15, color: LumiTokens.muted),
          const SizedBox(width: LumiTokens.space2),
          Expanded(
            child: Text(
              '"Don\'t forget to log $exampleName\'s reading today!"$suffix',
              style: LumiType.caption.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  // ── About & support ──

  Widget _buildAboutSection() {
    return _Section(
      title: 'About & support',
      child: _SettingsGroup(
        rows: [
          _SettingsRow(
            icon: Icons.feedback_outlined,
            title: 'Send feedback',
            onTap: () => showFeedbackSheet(
              context,
              userId: widget.user.id,
              userRole: widget.user.role.name,
            ),
          ),
          _SettingsRow(
            icon: Icons.network_check,
            title: 'Connection status',
            subtitle: 'Diagnostics for Lumi service & sync',
            onTap: () => context.push('/settings/service-status'),
          ),
          _SettingsRow(
            icon: Icons.info_outline,
            title: 'About Lumi',
            onTap: _showAboutDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildSignOut() {
    return _SettingsGroup(
      rows: [
        _SettingsRow(
          icon: Icons.logout_rounded,
          title: 'Sign out',
          tint: LumiTokens.tintRed,
          iconColor: LumiTokens.red,
          titleColor: LumiTokens.red,
          hideChevron: true,
          onTap: _handleSignOut,
        ),
      ],
    );
  }

  // ── Dialogs ──

  Future<void> _editRelationship() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => _RelationshipPicker(initialLabel: _relationshipLabel),
    );
    if (saved == null || saved == _relationshipLabel) return;
    setState(() => _relationshipLabel = saved);
    try {
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('parents')
          .doc(widget.user.id)
          .update({'relationshipLabel': saved});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relationship updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update relationship')),
        );
      }
    }
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.all(LumiTokens.space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LumiMascot(variant: LumiVariant.parent, size: 96),
              const SizedBox(height: LumiTokens.space4),
              Text('Lumi Reading Diary', style: LumiType.subhead),
              const SizedBox(height: LumiTokens.space1),
              Text('Version 1.0.0', style: LumiType.caption),
              const SizedBox(height: LumiTokens.space3),
              Text(
                'Making reading fun and trackable for every child. Lumi helps '
                'families build consistent reading habits together.',
                textAlign: TextAlign.center,
                style: LumiType.body,
              ),
              const SizedBox(height: LumiTokens.space4),
              const LegalLinksRow(accent: LumiTokens.green),
              const SizedBox(height: LumiTokens.space2),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Close',
                    style: LumiType.body.copyWith(
                        color: LumiTokens.green, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Section + grouped-list widgets
// ─────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: LumiTokens.space2),
          child: Text(
            title.toUpperCase(),
            style: LumiType.caption.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: LumiTokens.muted,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// A paper card whose rows are separated by inset dividers.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> rows;

  const _SettingsGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                indent: LumiTokens.space4,
                endIndent: LumiTokens.space4,
                color: LumiTokens.rule,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Color tint;
  final Color iconColor;
  final Color? titleColor;
  final bool accent;
  final bool hideChevron;
  final VoidCallback onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.tint = LumiTokens.tintGreen,
    this.iconColor = LumiTokens.green,
    this.titleColor,
    this.accent = false,
    this.hideChevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(LumiTokens.space4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: LumiTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LumiType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor ??
                          (accent ? LumiTokens.green : LumiTokens.ink),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, style: LumiType.caption),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: LumiTokens.space2),
              Text(value!, style: LumiType.caption),
            ],
            if (!hideChevron) ...[
              const SizedBox(width: LumiTokens.space2),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: LumiTokens.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LumiTokens.space3,
        vertical: LumiTokens.space1,
      ),
      decoration: BoxDecoration(
        color: LumiTokens.tintGreen,
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LumiTokens.green),
          const SizedBox(width: 4),
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Relationship picker dialog. Owns its own [TextEditingController] so it is
/// disposed when the dialog leaves the tree (after the exit animation).
class _RelationshipPicker extends StatefulWidget {
  const _RelationshipPicker({required this.initialLabel});

  final String? initialLabel;

  @override
  State<_RelationshipPicker> createState() => _RelationshipPickerState();
}

class _RelationshipPickerState extends State<_RelationshipPicker> {
  late String? _choice;
  late final TextEditingController _otherController;

  @override
  void initState() {
    super.initState();
    final label = widget.initialLabel;
    _choice = label != null && GuardianRelationship.presets.contains(label)
        ? label
        : (label == null ? null : GuardianRelationship.other);
    _otherController = TextEditingController(
      text: _choice == GuardianRelationship.other ? label : '',
    );
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  String? _resolveLabel() {
    if (_choice == null) return null;
    if (_choice == GuardianRelationship.other) {
      final t = _otherController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _choice;
  }

  @override
  Widget build(BuildContext context) {
    final options = [...GuardianRelationship.presets, GuardianRelationship.other];
    return AlertDialog(
      backgroundColor: LumiTokens.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      ),
      title: Text('Your relationship', style: LumiType.subhead),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text(option),
                  selected: _choice == option,
                  selectedColor: LumiTokens.tintGreen,
                  onSelected: (_) => setState(() => _choice = option),
                ),
            ],
          ),
          if (_choice == GuardianRelationship.other) ...[
            const SizedBox(height: LumiTokens.space3),
            TextField(
              controller: _otherController,
              autofocus: true,
              style: LumiType.body,
              decoration: InputDecoration(
                hintText: 'e.g. Aunt, Foster carer',
                hintStyle: LumiType.body.copyWith(color: LumiTokens.muted),
                filled: true,
                fillColor: LumiTokens.cream,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: LumiTokens.space3,
                  vertical: LumiTokens.space3,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.rule),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                  borderSide: const BorderSide(color: LumiTokens.green, width: 2),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: LumiType.body.copyWith(color: LumiTokens.muted)),
        ),
        TextButton(
          onPressed: _resolveLabel() == null
              ? null
              : () => Navigator.pop(context, _resolveLabel()),
          child: Text('Save',
              style: LumiType.body.copyWith(
                  color: LumiTokens.green, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
