import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_stat_card.dart';
import '../../core/widgets/lumi/teacher_settings_section.dart';
import '../../core/widgets/lumi/teacher_settings_item.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/user_model.dart';
import '../../data/models/school_model.dart';
import '../../services/firebase_service.dart';
import '../auth/login_screen.dart';
import 'user_management_screen.dart';
import 'class_management_screen.dart';
import 'database_migration_screen.dart';
import 'parent_linking_management_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  final UserModel user;

  const AdminHomeScreen({
    super.key,
    required this.user,
  });

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  int _selectedIndex = 0;
  SchoolModel? _school;
  bool _isLoading = true;

  // Statistics
  int _totalStudents = 0;
  int _totalTeachers = 0;
  int _totalClasses = 0;
  int _activeUsers = 0;

  @override
  void initState() {
    super.initState();
    // Role guard: redirect if user is not a school admin
    if (widget.user.role != UserRole.schoolAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/auth/login');
      });
      return;
    }
    _loadSchoolData();
  }

  Future<void> _loadSchoolData() async {
    try {
      if (widget.user.schoolId == null || widget.user.schoolId!.isEmpty) {
        debugPrint('Warning: User has no schoolId or empty schoolId');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Load school data
      final schoolDoc = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .get();

      if (schoolDoc.exists) {
        _school = SchoolModel.fromFirestore(schoolDoc);
      }

      // Load statistics using nested structure
      final studentsQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .collection('students')
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      final teachersQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .collection('users')
          .where('role', isEqualTo: 'teacher')
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      final classesQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .collection('classes')
          .where('isActive', isEqualTo: true)
          .count()
          .get();

      final activeUsersQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .collection('users')
          .count()
          .get();

      setState(() {
        _totalStudents = studentsQuery.count ?? 0;
        _totalTeachers = teachersQuery.count ?? 0;
        _totalClasses = classesQuery.count ?? 0;
        _activeUsers = activeUsersQuery.count ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading school data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Sign Out', style: TeacherTypography.h3),
        content: Text(
          'Are you sure you want to sign out?',
          style: TeacherTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.teacherPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warmOrange,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _firebaseService.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.teacherPrimary,
          ),
        ),
      );
    }

    if (_school == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: _buildNoSchoolView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardView(),
          _buildUsersView(),
          _buildClassesView(),
          _buildSettingsView(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 8,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.dashboard, 'Dashboard', 0),
                _buildNavItem(Icons.people, 'Users', 1),
                _buildNavItem(Icons.groups, 'Classes', 2),
                _buildNavItem(Icons.settings, 'Settings', 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.teacherPrimary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.teacherPrimary
                  : AppColors.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TeacherTypography.caption.copyWith(
                color: isSelected
                    ? AppColors.teacherPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppColors.teacherGradient,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(TeacherDimensions.radiusXL),
                  bottomRight: Radius.circular(TeacherDimensions.radiusXL),
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: AppColors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _school!.name,
                              style: TeacherTypography.h2.copyWith(
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'School Admin Dashboard',
                              style: TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.white,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Notifications coming soon'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 2x2 Statistics Grid using TeacherStatCard
                Row(
                  children: [
                    Expanded(
                      child: TeacherStatCard(
                        icon: Icons.school,
                        iconColor: AppColors.teacherPrimary,
                        iconBgColor: AppColors.teacherPrimaryLight,
                        value: _totalStudents.toString(),
                        label: 'Total Students',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TeacherStatCard(
                        icon: Icons.person,
                        iconColor: AppColors.skyBlue,
                        iconBgColor: AppColors.skyBlue.withValues(alpha: 0.15),
                        value: _totalTeachers.toString(),
                        label: 'Total Teachers',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TeacherStatCard(
                        icon: Icons.groups,
                        iconColor: AppColors.warmOrange,
                        iconBgColor: AppColors.warmOrange.withValues(alpha: 0.15),
                        value: _totalClasses.toString(),
                        label: 'Active Classes',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TeacherStatCard(
                        icon: Icons.people,
                        iconColor: AppColors.mintGreen,
                        iconBgColor: AppColors.mintGreen.withValues(alpha: 0.15),
                        value: _activeUsers.toString(),
                        label: 'Active Users',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Weekly Engagement Chart
                _buildEngagementChart(),

                const SizedBox(height: 24),

                // Quick Actions
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quick Actions', style: TeacherTypography.h3),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildQuickAction(
                            icon: Icons.person_add,
                            label: 'Add User',
                            color: AppColors.teacherPrimary,
                            onTap: () => setState(() => _selectedIndex = 1),
                          ),
                          _buildQuickAction(
                            icon: Icons.group_add,
                            label: 'Add Class',
                            color: AppColors.warmOrange,
                            onTap: () => setState(() => _selectedIndex = 2),
                          ),
                          _buildQuickAction(
                            icon: Icons.download,
                            label: 'Reports',
                            color: AppColors.mintGreen,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Reports feature coming soon'),
                                ),
                              );
                            },
                          ),
                          _buildQuickAction(
                            icon: Icons.qr_code,
                            label: 'Parent Links',
                            color: AppColors.warmOrange,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ParentLinkingManagementScreen(
                                    user: widget.user,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Recent Activity
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Recent Activity', style: TeacherTypography.h3),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('View all coming soon'),
                                ),
                              );
                            },
                            child: Text(
                              'View All',
                              style: TeacherTypography.bodyMedium.copyWith(
                                color: AppColors.teacherPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildRecentActivity(),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: child,
    );
  }

  Widget _buildEngagementChart() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weekly Engagement', style: TeacherTypography.h3),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _firebaseService.firestore
                .collection('schools')
                .doc(widget.user.schoolId!)
                .collection('readingLogs')
                .where('date',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime.now().subtract(const Duration(days: 7)),
                    ))
                .snapshots(),
            builder: (context, snapshot) {
              final logs = snapshot.data?.docs ?? [];

              // Group by day
              final Map<int, int> logsByDay = {};
              for (int i = 0; i < 7; i++) {
                logsByDay[i] = 0;
              }

              for (final doc in logs) {
                final data = doc.data() as Map<String, dynamic>;
                final date = (data['date'] as Timestamp).toDate();
                final dayIndex = 6 - DateTime.now().difference(date).inDays;
                if (dayIndex >= 0 && dayIndex < 7) {
                  logsByDay[dayIndex] = (logsByDay[dayIndex] ?? 0) + 1;
                }
              }

              final maxValue =
                  logsByDay.values.isEmpty ? 0 : logsByDay.values.reduce((a, b) => a > b ? a : b);

              return SizedBox(
                height: 180,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (index) {
                    final value = logsByDay[index] ?? 0;
                    final height = maxValue == 0
                        ? 20.0
                        : (value / maxValue * 140).clamp(20.0, 140.0);
                    final date = DateTime.now()
                        .subtract(Duration(days: 6 - index));
                    final dayLabel = DateFormat('E').format(date).substring(0, 1);

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          value.toString(),
                          style: TeacherTypography.caption,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: height,
                          decoration: BoxDecoration(
                            color: AppColors.teacherPrimary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dayLabel,
                          style: TeacherTypography.caption,
                        ),
                      ],
                    );
                  }),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TeacherTypography.caption.copyWith(
              color: AppColors.charcoal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivity() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId!)
          .collection('readingLogs')
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.teacherPrimary,
            ),
          );
        }

        final logs = snapshot.data!.docs;

        if (logs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text('No Activity', style: TeacherTypography.h3),
                  const SizedBox(height: 4),
                  Text(
                    'No recent activity',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: logs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['createdAt'] as Timestamp).toDate();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.teacherPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    child: const Icon(
                      Icons.book,
                      color: AppColors.teacherPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New reading log',
                          style: TeacherTypography.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM dd, hh:mm a').format(date),
                          style: TeacherTypography.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildUsersView() {
    return UserManagementScreen(adminUser: widget.user);
  }

  Widget _buildClassesView() {
    return ClassManagementScreen(adminUser: widget.user);
  }

  Widget _buildSettingsView() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: TeacherTypography.h1),
            const SizedBox(height: 24),

            // School Settings Section
            TeacherSettingsSection(
              title: 'School',
              items: [
                TeacherSettingsItem(
                  icon: Icons.school,
                  iconBgColor: AppColors.teacherPrimary,
                  label: 'School Information',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('School info coming soon')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.notifications,
                  iconBgColor: AppColors.warmOrange,
                  label: 'Notifications',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Notifications coming soon')),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Database Section
            TeacherSettingsSection(
              title: 'Database',
              items: [
                TeacherSettingsItem(
                  icon: Icons.cloud_sync,
                  iconBgColor: AppColors.skyBlue,
                  label: 'Database Migration',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.skyBlue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
                    ),
                    child: Text(
                      'RECOMMENDED',
                      style: TeacherTypography.caption.copyWith(
                        color: AppColors.skyBlue,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DatabaseMigrationScreen(
                          adminUser: widget.user,
                        ),
                      ),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.backup,
                  iconBgColor: AppColors.mintGreen,
                  label: 'Backup & Export',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backup feature coming soon')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.link,
                  iconBgColor: AppColors.warmOrange,
                  label: 'Parent Linking Codes',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ParentLinkingManagementScreen(
                          user: widget.user,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            // App Section
            TeacherSettingsSection(
              title: 'App',
              items: [
                TeacherSettingsItem(
                  icon: Icons.person,
                  iconBgColor: AppColors.teacherPrimary,
                  label: 'View Profile',
                  onTap: () {
                    // Show profile info in a dialog
                    _showProfileDialog();
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.help_outline,
                  iconBgColor: AppColors.skyBlue,
                  label: 'Help & Support',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Help centre coming soon')),
                    );
                  },
                ),
                TeacherSettingsItem(
                  icon: Icons.info_outline,
                  iconBgColor: AppColors.charcoal.withValues(alpha: 0.6),
                  label: 'About',
                  trailing: Text(
                    'v1.0.0',
                    style: TeacherTypography.bodySmall,
                  ),
                  onTap: () {
                    showAboutDialog(
                      context: context,
                      applicationName: 'Lumi Reading Diary',
                      applicationVersion: '1.0.0',
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Sign Out Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _handleSignOut,
                icon: const Icon(Icons.logout, size: 20),
                label: Text('Sign Out', style: TeacherTypography.buttonText),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warmOrange,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
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

  void _showProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        ),
        title: Text('Admin Profile', style: TeacherTypography.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.teacherPrimary,
              child: Text(
                widget.user.fullName.isNotEmpty
                    ? widget.user.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 32,
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(widget.user.fullName, style: TeacherTypography.h2),
            const SizedBox(height: 4),
            Text(
              widget.user.email,
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.teacherPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
              ),
              child: Text(
                'School Administrator',
                style: TeacherTypography.bodySmall.copyWith(
                  color: AppColors.teacherPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            _buildProfileInfoRow(Icons.school, _school?.name ?? 'N/A'),
            const SizedBox(height: 8),
            _buildProfileInfoRow(Icons.people, '$_totalStudents students'),
            const SizedBox(height: 8),
            _buildProfileInfoRow(Icons.groups, '$_totalClasses classes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.teacherPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.teacherPrimary),
        const SizedBox(width: 8),
        Text(text, style: TeacherTypography.bodyMedium),
      ],
    );
  }

  Widget _buildNoSchoolView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                color: AppColors.teacherPrimary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school,
                size: 80,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No School Configured',
              style: TeacherTypography.h2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Please contact support to set up your school.',
              style: TeacherTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
