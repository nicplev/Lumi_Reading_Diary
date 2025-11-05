import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/minimal_theme.dart';
import '../../core/widgets/minimal/minimal_widgets.dart';
import '../../data/models/user_model.dart';
import '../../data/models/school_model.dart';
import '../../services/firebase_service.dart';
import '../auth/login_screen.dart';
import 'user_management_screen.dart';
import 'class_management_screen.dart';
import 'database_migration_screen.dart';

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
        backgroundColor: MinimalTheme.cream,
        body: const Center(
          child: CircularProgressIndicator(
            color: MinimalTheme.primaryPurple,
          ),
        ),
      );
    }

    if (_school == null) {
      return Scaffold(
        backgroundColor: MinimalTheme.cream,
        body: _buildNoSchoolView(),
      );
    }

    return Scaffold(
      backgroundColor: MinimalTheme.cream,
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildDashboardView(),
          _buildUsersView(),
          _buildClassesView(),
          _buildSettingsView(),
          _buildProfileView(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: MinimalTheme.white,
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
              horizontal: MinimalTheme.spaceM,
              vertical: MinimalTheme.spaceS,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(Icons.dashboard, 'Dashboard', 0),
                _buildNavItem(Icons.people, 'Users', 1),
                _buildNavItem(Icons.groups, 'Classes', 2),
                _buildNavItem(Icons.settings, 'Settings', 3),
                _buildNavItem(Icons.person, 'Profile', 4),
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
      borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? MinimalTheme.lightPurple.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? MinimalTheme.primaryPurple
                  : MinimalTheme.textSecondary,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected
                    ? MinimalTheme.primaryPurple
                    : MinimalTheme.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
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
              decoration: BoxDecoration(
                gradient: MinimalTheme.purpleGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(MinimalTheme.radiusLarge),
                  bottomRight: Radius.circular(MinimalTheme.radiusLarge),
                ),
              ),
              padding: const EdgeInsets.all(MinimalTheme.spaceL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: MinimalTheme.white.withValues(alpha: 0.2),
                          borderRadius:
                              BorderRadius.circular(MinimalTheme.radiusMedium),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: MinimalTheme.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: MinimalTheme.spaceM),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _school!.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: MinimalTheme.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'School Admin Dashboard',
                              style: TextStyle(
                                fontSize: 14,
                                color: MinimalTheme.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_outlined,
                          color: MinimalTheme.white,
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
            padding: const EdgeInsets.all(MinimalTheme.spaceL),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Statistics Grid
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Total Students',
                        value: _totalStudents.toString(),
                        icon: Icons.school,
                        iconColor: MinimalTheme.primaryPurple,
                      ),
                    ),
                    const SizedBox(width: MinimalTheme.spaceM),
                    Expanded(
                      child: StatCard(
                        label: 'Total Teachers',
                        value: _totalTeachers.toString(),
                        icon: Icons.person,
                        iconColor: MinimalTheme.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MinimalTheme.spaceM),
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Active Classes',
                        value: _totalClasses.toString(),
                        icon: Icons.groups,
                        iconColor: MinimalTheme.darkPurple,
                      ),
                    ),
                    const SizedBox(width: MinimalTheme.spaceM),
                    Expanded(
                      child: StatCard(
                        label: 'Active Users',
                        value: _activeUsers.toString(),
                        icon: Icons.people,
                        iconColor: MinimalTheme.green,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: MinimalTheme.spaceL),

                // Weekly Engagement Chart
                _buildEngagementChart(),

                const SizedBox(height: MinimalTheme.spaceL),

                // Quick Actions
                RoundedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: MinimalTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: MinimalTheme.spaceM),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildQuickAction(
                            icon: Icons.person_add,
                            label: 'Add User',
                            color: MinimalTheme.primaryPurple,
                            onTap: () => setState(() => _selectedIndex = 1),
                          ),
                          _buildQuickAction(
                            icon: Icons.group_add,
                            label: 'Add Class',
                            color: MinimalTheme.darkPurple,
                            onTap: () => setState(() => _selectedIndex = 2),
                          ),
                          _buildQuickAction(
                            icon: Icons.download,
                            label: 'Reports',
                            color: MinimalTheme.green,
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
                            label: 'Invites',
                            color: MinimalTheme.orange,
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Invitation system coming soon'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: MinimalTheme.spaceL),

                // Recent Activity
                RoundedCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Recent Activity',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: MinimalTheme.textPrimary,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('View all coming soon'),
                                ),
                              );
                            },
                            child: const Text(
                              'View All',
                              style: TextStyle(
                                color: MinimalTheme.primaryPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: MinimalTheme.spaceM),
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

  Widget _buildEngagementChart() {
    return RoundedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Engagement',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: MinimalTheme.textPrimary,
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceM),
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
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: MinimalTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: height,
                          decoration: BoxDecoration(
                            gradient: MinimalTheme.purpleGradient,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dayLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MinimalTheme.textSecondary,
                          ),
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
      borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: MinimalTheme.spaceS),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: MinimalTheme.textPrimary,
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
              color: MinimalTheme.primaryPurple,
            ),
          );
        }

        final logs = snapshot.data!.docs;

        if (logs.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'No Activity',
            message: 'No recent activity',
          );
        }

        return Column(
          children: logs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final date = (data['createdAt'] as Timestamp).toDate();
            return Padding(
              padding: const EdgeInsets.only(bottom: MinimalTheme.spaceM),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color:
                          MinimalTheme.lightPurple.withValues(alpha: 0.5),
                      borderRadius:
                          BorderRadius.circular(MinimalTheme.radiusMedium),
                    ),
                    child: const Icon(
                      Icons.book,
                      color: MinimalTheme.primaryPurple,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: MinimalTheme.spaceM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New reading log',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: MinimalTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM dd, hh:mm a').format(date),
                          style: const TextStyle(
                            fontSize: 12,
                            color: MinimalTheme.textSecondary,
                          ),
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
        padding: const EdgeInsets.all(MinimalTheme.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textPrimary,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceL),

            // School Settings Section
            const Text(
              'School Settings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceM),
            RoundedCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.school,
                    iconColor: MinimalTheme.primaryPurple,
                    title: 'School Information',
                    subtitle: 'View and edit school details',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('School info coming soon'),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _buildSettingsTile(
                    icon: Icons.notifications,
                    iconColor: MinimalTheme.orange,
                    title: 'Notifications',
                    subtitle: 'Configure notification settings',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Notifications coming soon'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: MinimalTheme.spaceL),

            // Database Section
            const Text(
              'Database',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceM),
            RoundedCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.cloud_sync,
                    iconColor: MinimalTheme.darkPurple,
                    title: 'Database Migration',
                    subtitle: 'Migrate to optimised structure',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MinimalTheme.blue.withValues(alpha: 0.15),
                        borderRadius:
                            BorderRadius.circular(MinimalTheme.radiusPill),
                      ),
                      child: const Text(
                        'RECOMMENDED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: MinimalTheme.blue,
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
                  const Divider(height: 1),
                  _buildSettingsTile(
                    icon: Icons.backup,
                    iconColor: MinimalTheme.green,
                    title: 'Backup & Export',
                    subtitle: 'Export school data',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Backup feature coming soon'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: MinimalTheme.spaceL),

            // App Settings Section
            const Text(
              'App Settings',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceM),
            RoundedCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.help_outline,
                    iconColor: MinimalTheme.blue,
                    title: 'Help & Support',
                    subtitle: null,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Help centre coming soon'),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1),
                  _buildSettingsTile(
                    icon: Icons.info_outline,
                    iconColor: MinimalTheme.textSecondary,
                    title: 'About',
                    subtitle: 'Version 1.0.0',
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(MinimalTheme.spaceM),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(MinimalTheme.radiusMedium),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: MinimalTheme.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MinimalTheme.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MinimalTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  color: MinimalTheme.textSecondary,
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileView() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: MinimalTheme.spaceL),

            // Profile Card
            Padding(
              padding: const EdgeInsets.all(MinimalTheme.spaceL),
              child: RoundedCard(
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: MinimalTheme.purpleGradient,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.user.fullName.isNotEmpty
                              ? widget.user.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 48,
                            color: MinimalTheme.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: MinimalTheme.spaceM),
                    Text(
                      widget.user.fullName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: MinimalTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email,
                      style: const TextStyle(
                        fontSize: 14,
                        color: MinimalTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: MinimalTheme.spaceM),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: MinimalTheme.lightPurple.withValues(alpha: 0.5),
                        borderRadius:
                            BorderRadius.circular(MinimalTheme.radiusPill),
                      ),
                      child: const Text(
                        'School Administrator',
                        style: TextStyle(
                          fontSize: 14,
                          color: MinimalTheme.primaryPurple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // School Info Card
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MinimalTheme.spaceL,
              ),
              child: RoundedCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'School Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: MinimalTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: MinimalTheme.spaceM),
                    _buildInfoRow(Icons.school, _school?.name ?? 'N/A'),
                    const SizedBox(height: MinimalTheme.spaceS),
                    _buildInfoRow(
                      Icons.people,
                      '$_totalStudents students',
                    ),
                    const SizedBox(height: MinimalTheme.spaceS),
                    _buildInfoRow(
                      Icons.groups,
                      '$_totalClasses classes',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: MinimalTheme.spaceL),

            // Sign out button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MinimalTheme.spaceL,
              ),
              child: PillButton(
                text: 'Sign Out',
                onPressed: _handleSignOut,
                backgroundColor: MinimalTheme.orange,
              ),
            ),

            const SizedBox(height: MinimalTheme.spaceL),

            // Version info
            const Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: MinimalTheme.textSecondary,
              ),
            ),

            const SizedBox(height: MinimalTheme.spaceL),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: MinimalTheme.primaryPurple,
        ),
        const SizedBox(width: MinimalTheme.spaceS),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: MinimalTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildNoSchoolView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MinimalTheme.spaceL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                gradient: MinimalTheme.purpleGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school,
                size: 80,
                color: MinimalTheme.white,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceL),
            const Text(
              'No School Configured',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: MinimalTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MinimalTheme.spaceM),
            const Text(
              'Please contact support to set up your school.',
              style: TextStyle(
                fontSize: 16,
                color: MinimalTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
