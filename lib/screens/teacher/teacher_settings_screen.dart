import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/dev_access.dart';
import '../../core/services/dev_access_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
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

  /// Dev-access flag — gates surfaces still in development. Source of truth is
  /// the `devAccessEmails` allowlist managed in the super-admin portal
  /// (Operations → Dev Access).
  final DevAccessService _devAccess = DevAccessService.instance;

  // Teacher's classes (for class picker navigation)
  List<ClassModel> _classes = [];
  bool _loadingClasses = true;
  bool _levelsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadReadingLevelOptions();
    // Rebuild if dev-access flips (e.g. the Firestore lookup resolves after a
    // session resume, or a super-admin grants/revokes access).
    _devAccess.addListener(_onDevAccessChanged);
  }

  @override
  void dispose() {
    _devAccess.removeListener(_onDevAccessChanged);
    super.dispose();
  }

  void _onDevAccessChanged() {
    if (mounted) setState(() {});
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
          top: Radius.circular(LumiTokens.radiusXL),
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
                      style: LumiType.subhead),
                ),
                const SizedBox(height: 8),
                ..._classes.map(
                  (cls) => ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            LumiTokens.muted.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.class_,
                          color: LumiTokens.ink, size: 20),
                    ),
                    title: Text(cls.name,
                        style: LumiType.body
                            .copyWith(fontWeight: FontWeight.w600)),
                    subtitle: cls.room != null
                        ? Text('Room ${cls.room}',
                            style: LumiType.caption)
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


  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: LumiTokens.red.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_stories,
                  color: LumiTokens.red, size: 22),
            ),
            const SizedBox(width: 12),
            Text('Lumi', style: LumiType.subhead),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0',
                style: LumiType.body
                    .copyWith(color: LumiTokens.muted)),
            const SizedBox(height: 8),
            Text('Reading Tracker for Schools', style: LumiType.body),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: LumiType.button
                    .copyWith(color: LumiTokens.red)),
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
          borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        ),
        title: Text('Sign Out', style: LumiType.subhead),
        content: Text(
          'Are you sure you want to sign out?',
          style: LumiType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: LumiType.button
                    .copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out',
                style: LumiType.button
                    .copyWith(color: LumiTokens.red)),
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
        color = LumiTokens.green;
        break;
      case SyncStatus.syncing:
        label = 'Syncing...';
        color = LumiTokens.ink;
        break;
      case SyncStatus.pending:
        label = '$pendingCount pending';
        color = LumiTokens.yellow;
        break;
      case SyncStatus.offline:
        label = 'Offline';
        color = LumiTokens.muted;
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
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: InkWell(
        onTap: _handleSignOut,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 9,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: LumiTokens.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.logout_rounded,
                    size: 18, color: LumiTokens.red),
              ),
              const SizedBox(width: 14),
              Text(
                'Log Out',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: LumiTokens.red,
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
          style: LumiType.caption.copyWith(
            color: LumiTokens.muted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: LumiTokens.cream,
      child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: LumiType.heading)
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
                    iconBgColor: LumiTokens.muted,
                    label: 'Reading Levels',
                    onTap: () =>
                        _navigateWithClass('/teacher/level-management'),
                  ),
                TeacherSettingsItem(
                  icon: Icons.groups,
                  iconBgColor: LumiTokens.muted,
                  label: 'Reading Groups',
                  onTap: () => _navigateWithClass('/teacher/reading-groups'),
                ),
                // Class Reports is still in development — visible only to
                // dev-access accounts until it ships in a later update.
                if (hasDevAccess())
                  TeacherSettingsItem(
                    icon: Icons.assessment,
                    iconBgColor: LumiTokens.muted,
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
                  iconBgColor: LumiTokens.muted,
                  label: 'Parent/Guardian Notifications',
                  onTap: () {
                    context.push('/teacher/notifications');
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
                  icon: Icons.sync,
                  iconBgColor: LumiTokens.muted,
                  label: 'Sync Status',
                  trailing: _buildSyncStatusTrailing(),
                ),
                TeacherSettingsItem(
                  icon: Icons.network_check,
                  iconBgColor: LumiTokens.muted,
                  label: 'Connection status',
                  onTap: () => context.push('/settings/service-status'),
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
                  iconBgColor: LumiTokens.muted,
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
                  iconBgColor: LumiTokens.muted,
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
      ),
    );
  }
}
