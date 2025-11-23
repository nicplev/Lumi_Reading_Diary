import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_card.dart';
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
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign Out'),
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
        backgroundColor: AppColors.offWhite,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.rosePink,
          ),
        ),
      );
    }

    if (_school == null) {
      return Scaffold(
        backgroundColor: AppColors.offWhite,
        body: _buildNoSchoolView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.offWhite,
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
              horizontal: LumiSpacing.m,
              vertical: LumiSpacing.s,
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
      borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.rosePink.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.rosePink
                  : AppColors.charcoal.withValues(alpha: 0.7),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: LumiTextStyles.label(
                color: isSelected
                    ? AppColors.rosePink
                    : AppColors.charcoal.withValues(alpha: 0.7),
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
                color: AppColors.rosePink,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(LumiBorders.radiusLarge),
                  bottomRight: Radius.circular(LumiBorders.radiusLarge),
                ),
              ),
              padding: const EdgeInsets.all(LumiSpacing.l),
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
                          borderRadius:
                              BorderRadius.circular(LumiBorders.radiusMedium),
                        ),
                        child: const Icon(
                          Icons.school,
                          color: AppColors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: LumiSpacing.m),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _school!.name,
                              style: LumiTextStyles.label(
                                
                                color: AppColors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'School Admin Dashboard',
                              style: LumiTextStyles.body(color: AppColors.white),
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
            padding: const EdgeInsets.all(LumiSpacing.l),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Statistics Grid
                Row(
                  children: [
                    Expanded(
                      child: LumiCard(
                        child: Padding(
                          padding: const EdgeInsets.all(LumiSpacing.m),
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.rosePink.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
                                ),
                                child: const Icon(
                                  Icons.school,
                                  color: AppColors.rosePink,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: LumiSpacing.s),
                              Text(
                                _totalStudents.toString(),
                                style: LumiTextStyles.h2(color: AppColors.charcoal),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Students',
                                style: LumiTextStyles.label(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LumiSpacing.m),
                    Expanded(
                      child: LumiCard(
                        child: Padding(
                          padding: const EdgeInsets.all(LumiSpacing.m),
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.skyBlue.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: AppColors.skyBlue,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: LumiSpacing.s),
                              Text(
                                _totalTeachers.toString(),
                                style: LumiTextStyles.h2(color: AppColors.charcoal),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Teachers',
                                style: LumiTextStyles.label(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LumiSpacing.m),
                Row(
                  children: [
                    Expanded(
                      child: LumiCard(
                        child: Padding(
                          padding: const EdgeInsets.all(LumiSpacing.m),
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.warmOrange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
                                ),
                                child: const Icon(
                                  Icons.groups,
                                  color: AppColors.warmOrange,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: LumiSpacing.s),
                              Text(
                                _totalClasses.toString(),
                                style: LumiTextStyles.h2(color: AppColors.charcoal),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Active Classes',
                                style: LumiTextStyles.label(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LumiSpacing.m),
                    Expanded(
                      child: LumiCard(
                        child: Padding(
                          padding: const EdgeInsets.all(LumiSpacing.m),
                          child: Column(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.mintGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
                                ),
                                child: const Icon(
                                  Icons.people,
                                  color: AppColors.mintGreen,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(height: LumiSpacing.s),
                              Text(
                                _activeUsers.toString(),
                                style: LumiTextStyles.h2(color: AppColors.charcoal),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Active Users',
                                style: LumiTextStyles.label(
                                  color: AppColors.charcoal.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: LumiSpacing.l),

                // Weekly Engagement Chart
                _buildEngagementChart(),

                const SizedBox(height: LumiSpacing.l),

                // Quick Actions
                LumiCard(
                  child: Padding(
                    padding: const EdgeInsets.all(LumiSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Actions',
                          style: LumiTextStyles.h3(color: AppColors.charcoal),
                        ),
                      const SizedBox(height: LumiSpacing.m),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildQuickAction(
                            icon: Icons.person_add,
                            label: 'Add User',
                            color: AppColors.rosePink,
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
                ),

                const SizedBox(height: LumiSpacing.l),

                // Recent Activity
                LumiCard(
                  child: Padding(
                    padding: const EdgeInsets.all(LumiSpacing.m),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Recent Activity',
                              style: LumiTextStyles.h3(color: AppColors.charcoal),
                            ),
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
                              style: LumiTextStyles.label(
                                color: AppColors.rosePink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: LumiSpacing.m),
                      _buildRecentActivity(),
                    ],
                    ),
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
    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(LumiSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly Engagement',
              style: LumiTextStyles.h3(color: AppColors.charcoal),
            ),
          const SizedBox(height: LumiSpacing.m),
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
                          style: LumiTextStyles.label(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 32,
                          height: height,
                          decoration: BoxDecoration(
                            color: AppColors.rosePink,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          dayLabel,
                          style: LumiTextStyles.label(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
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
      borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(height: LumiSpacing.s),
          Text(
            label,
            style: LumiTextStyles.label(color: AppColors.charcoal),
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
              color: AppColors.rosePink,
            ),
          );
        }

        final logs = snapshot.data!.docs;

        if (logs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(LumiSpacing.l),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: AppColors.charcoal.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: LumiSpacing.m),
                  Text(
                    'No Activity',
                    style: LumiTextStyles.h3(color: AppColors.charcoal),
                  ),
                  const SizedBox(height: LumiSpacing.s),
                  Text(
                    'No recent activity',
                    style: LumiTextStyles.body(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
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
              padding: const EdgeInsets.only(bottom: LumiSpacing.m),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.rosePink.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(LumiBorders.radiusMedium),
                    ),
                    child: const Icon(
                      Icons.book,
                      color: AppColors.rosePink,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: LumiSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New reading log',
                          style: LumiTextStyles.body(color: AppColors.charcoal),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('MMM dd, hh:mm a').format(date),
                          style: LumiTextStyles.label(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
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
        padding: const EdgeInsets.all(LumiSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: LumiTextStyles.h1(color: AppColors.charcoal),
            ),
            const SizedBox(height: LumiSpacing.l),

            // School Settings Section
            Text(
              'School Settings',
              style: LumiTextStyles.overline(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),
            LumiCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.school,
                    iconColor: AppColors.rosePink,
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
                    iconColor: AppColors.warmOrange,
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

            const SizedBox(height: LumiSpacing.l),

            // Database Section
            Text(
              'Database',
              style: LumiTextStyles.overline(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),
            LumiCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.cloud_sync,
                    iconColor: AppColors.warmOrange,
                    title: 'Database Migration',
                    subtitle: 'Migrate to optimised structure',
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.skyBlue.withValues(alpha: 0.15),
                        borderRadius:
                            BorderRadius.circular(100),
                      ),
                      child: Text(
                        'RECOMMENDED',
                        style: LumiTextStyles.label(
                          color: AppColors.skyBlue,
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
                    iconColor: AppColors.mintGreen,
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

            const SizedBox(height: LumiSpacing.l),

            // App Settings Section
            Text(
              'App Settings',
              style: LumiTextStyles.overline(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),
            LumiCard(
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.help_outline,
                    iconColor: AppColors.skyBlue,
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
                    iconColor: AppColors.charcoal.withValues(alpha: 0.7),
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
        padding: const EdgeInsets.all(LumiSpacing.m),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: LumiSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: LumiTextStyles.body(color: AppColors.charcoal),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: LumiTextStyles.label(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  color: AppColors.charcoal.withValues(alpha: 0.7),
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
            const SizedBox(height: LumiSpacing.l),

            // Profile Card
            Padding(
              padding: const EdgeInsets.all(LumiSpacing.l),
              child: LumiCard(
                child: Padding(
                  padding: const EdgeInsets.all(LumiSpacing.m),
                  child: Column(
                    children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.rosePink,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.user.fullName.isNotEmpty
                              ? widget.user.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 48,
                            color: AppColors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: LumiSpacing.m),
                    Text(
                      widget.user.fullName,
                      style: LumiTextStyles.h2(color: AppColors.charcoal),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.user.email,
                      style: LumiTextStyles.body(
                        color: AppColors.charcoal.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: LumiSpacing.m),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.rosePink.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(100),
                      ),
                      child: Text(
                        'School Administrator',
                        style: LumiTextStyles.label(
                          color: AppColors.rosePink,
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              ),
            ),

            // School Info Card
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumiSpacing.l,
              ),
              child: LumiCard(
                child: Padding(
                  padding: const EdgeInsets.all(LumiSpacing.m),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                    Text(
                      'School Information',
                      style: LumiTextStyles.label(
                        
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(height: LumiSpacing.m),
                    _buildInfoRow(Icons.school, _school?.name ?? 'N/A'),
                    const SizedBox(height: LumiSpacing.s),
                    _buildInfoRow(
                      Icons.people,
                      '$_totalStudents students',
                    ),
                    const SizedBox(height: LumiSpacing.s),
                    _buildInfoRow(
                      Icons.groups,
                      '$_totalClasses classes',
                    ),
                  ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: LumiSpacing.l),

            // Sign out button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumiSpacing.l,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _handleSignOut,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warmOrange,
                    foregroundColor: AppColors.white,
                    padding: const EdgeInsets.symmetric(vertical: LumiSpacing.m),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(LumiBorders.radiusMedium),
                    ),
                  ),
                  child: Text(
                    'Sign Out',
                    style: LumiTextStyles.button(color: AppColors.white),
                  ),
                ),
              ),
            ),

            const SizedBox(height: LumiSpacing.l),

            // Version info
            Text(
              'Version 1.0.0',
              style: LumiTextStyles.label(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: LumiSpacing.l),
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
          color: AppColors.rosePink,
        ),
        const SizedBox(width: LumiSpacing.s),
        Text(
          text,
          style: LumiTextStyles.label(
            color: AppColors.charcoal,
          ),
        ),
      ],
    );
  }

  Widget _buildNoSchoolView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LumiSpacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.rosePink,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school,
                size: 80,
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: LumiSpacing.l),
            Text(
              'No School Configured',
              style: LumiTextStyles.label(
                
                color: AppColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LumiSpacing.m),
            Text(
              'Please contact support to set up your school.',
              style: LumiTextStyles.label(
                
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
