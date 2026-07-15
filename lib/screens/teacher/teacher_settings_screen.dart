import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/sign_out_flow.dart';
import '../../core/config/dev_access.dart';
import '../../core/services/app_icon_service.dart';
import '../../core/services/dev_access_service.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/feedback_widget.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import '../../core/widgets/lumi/legal_links_row.dart';
import '../../core/widgets/lumi/lumi_toast.dart';
import '../../data/models/class_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/mfa_settings_service.dart';
import '../../services/offline_service.dart';
import '../../services/reading_level_service.dart';
import '../settings/mfa_settings_sheet.dart';

/// Teacher Settings Screen (Tab 4)
///
/// Production-ready settings with persisted preferences, real navigation,
/// and cache/sync management.
class TeacherSettingsScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback? onReplayTour;

  const TeacherSettingsScreen({
    super.key,
    required this.user,
    this.onReplayTour,
  });

  @override
  State<TeacherSettingsScreen> createState() => _TeacherSettingsScreenState();
}

class _TeacherSettingsScreenState extends State<TeacherSettingsScreen>
    with WidgetsBindingObserver {
  final ReadingLevelService _readingLevelService = ReadingLevelService();
  final MfaSettingsService _mfaSettingsService = MfaSettingsService();

  /// Dev-access flag — gates surfaces still in development. Source of truth is
  /// the `devAccessEmails` allowlist managed in the super-admin portal
  /// (Operations → Dev Access).
  final DevAccessService _devAccess = DevAccessService.instance;

  // Teacher's classes (for class picker navigation)
  List<ClassModel> _classes = [];
  bool _loadingClasses = true;
  bool _levelsEnabled = false;
  MfaStatus? _mfaStatus;
  bool _mfaStatusLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadClasses();
    _loadReadingLevelOptions();
    _loadMfaStatus();
    // Rebuild if dev-access flips (e.g. the server lookup resolves after a
    // session resume, or a super-admin grants/revokes access).
    _devAccess.addListener(_onDevAccessChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _devAccess.removeListener(_onDevAccessChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh the MFA row when the app comes back to the foreground — the
    // enrol/disable flow bounces through Safari (reCAPTCHA), so the on-screen
    // On/Off badge can otherwise lag behind the real state until a cold start.
    if (state == AppLifecycleState.resumed) _loadMfaStatus();
  }

  void _onDevAccessChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadMfaStatus() async {
    setState(() => _mfaStatusLoading = true);
    try {
      final status = await _mfaSettingsService.loadStatus();
      if (mounted) setState(() => _mfaStatus = status);
    } catch (_) {
      if (mounted) setState(() => _mfaStatus = null);
    } finally {
      if (mounted) setState(() => _mfaStatusLoading = false);
    }
  }

  Future<void> _openMfaSettings() async {
    await showMfaSettingsSheet(
      context: context,
      user: widget.user,
      accentColor: LumiTokens.red,
    );
    // Always re-read on close: enrolment can complete out-of-band (via the
    // reCAPTCHA recovery screen) without the sheet reporting a change, so the
    // sheet's return value isn't a reliable signal to refresh the row.
    await _loadMfaStatus();
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
      showLumiToast(
        message: 'No classes assigned to your account.',
        type: LumiToastType.info,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Select a Class', style: LumiType.subhead),
                ),
                const SizedBox(height: 8),
                ..._classes.map(
                  (cls) => ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: LumiTokens.muted.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.class_,
                          color: LumiTokens.ink, size: 20),
                    ),
                    title: Text(cls.name,
                        style: LumiType.body
                            .copyWith(fontWeight: FontWeight.w600)),
                    subtitle: cls.room != null
                        ? Text('Room ${cls.room}', style: LumiType.caption)
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
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Image.asset(
                'assets/staff_characters/la_green.png',
                fit: BoxFit.contain,
              ),
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
                style: LumiType.body.copyWith(color: LumiTokens.muted)),
            const SizedBox(height: 8),
            Text('Reading Tracker for Schools', style: LumiType.body),
            const SizedBox(height: LumiTokens.space4),
            const LegalLinksRow(accent: LumiTokens.red),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: LumiType.button.copyWith(color: LumiTokens.red)),
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
                style: LumiType.button.copyWith(color: LumiTokens.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out',
                style: LumiType.button.copyWith(color: LumiTokens.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!mounted) return;
      await signOutAndNavigateToLogin(context);
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

  Widget _buildMfaStatusTrailing() {
    String label;
    Color color;
    if (_mfaStatusLoading) {
      label = 'Checking';
      color = LumiTokens.muted;
    } else if (_mfaStatus?.enabled == true) {
      label = 'On';
      color = LumiTokens.green;
    } else {
      label = 'Off';
      color = LumiTokens.muted;
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
                  TeacherSettingsItem(
                    icon: Icons.emoji_events,
                    iconBgColor: LumiTokens.muted,
                    label: 'Awards',
                    onTap: () => _navigateWithClass('/teacher/awards'),
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

              // SECURITY section
              TeacherSettingsSection(
                title: 'Security',
                items: [
                  TeacherSettingsItem(
                    icon: Icons.manage_accounts_outlined,
                    iconBgColor: LumiTokens.muted,
                    label: 'Account',
                    onTap: () => context.push(
                      '/settings/account',
                      extra: widget.user,
                    ),
                  ),
                  TeacherSettingsItem(
                    icon: Icons.shield_outlined,
                    iconBgColor: LumiTokens.muted,
                    label: 'SMS verification',
                    trailing: _buildMfaStatusTrailing(),
                    onTap: _openMfaSettings,
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 300.ms, delay: 150.ms)
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
                  if (widget.onReplayTour != null)
                    TeacherSettingsItem(
                      icon: Icons.route_outlined,
                      iconBgColor: LumiTokens.muted,
                      label: 'Replay app tour',
                      onTap: widget.onReplayTour,
                    ),
                  // The app-icon pack is still in testing — visible only to
                  // dev-access accounts until it ships publicly. iOS-only.
                  if (hasDevAccess() && AppIconService.isSupportedPlatform)
                    TeacherSettingsItem(
                      icon: Icons.apps,
                      iconBgColor: LumiTokens.muted,
                      label: 'App Icon',
                      onTap: () => context.push('/settings/app-icon'),
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
