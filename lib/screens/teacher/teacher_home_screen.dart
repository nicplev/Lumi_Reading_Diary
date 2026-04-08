import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/class_model.dart';
import '../../services/firebase_service.dart';
import 'dashboard/teacher_dashboard_view.dart';
import 'teacher_classroom_screen.dart';
import 'teacher_library_screen.dart';
import 'teacher_settings_screen.dart';

class TeacherHomeScreen extends StatefulWidget {
  final UserModel user;

  const TeacherHomeScreen({
    super.key,
    required this.user,
  });

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseService _firebaseService = FirebaseService.instance;
  int _selectedIndex = 0;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  bool _isLoading = true;

  late final AnimationController _tabAnimController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tabAnimController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _tabAnimController, curve: Curves.easeOut),
    );
    _tabAnimController.value = 1.0;

    // Role guard: redirect if user is not a teacher or admin
    if (widget.user.role != UserRole.teacher &&
        widget.user.role != UserRole.schoolAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/auth/login');
      });
      return;
    }
    _loadClasses();
  }

  @override
  void dispose() {
    _tabAnimController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    _tabAnimController.value = 0.0;
    setState(() => _selectedIndex = index);
    _tabAnimController.forward();
  }

  Future<void> _loadClasses() async {
    try {
      final List<ClassModel> classes = [];

      final classQuery = await _firebaseService.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('classes')
          .where('teacherIds', arrayContains: widget.user.id)
          .where('isActive', isEqualTo: true)
          .get();

      for (var doc in classQuery.docs) {
        classes.add(ClassModel.fromFirestore(doc));
      }

      setState(() {
        _classes = classes;
        if (classes.isNotEmpty) {
          _selectedClass = classes.first;
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading classes: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: AppColors.error),
            ),
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
    return Theme(
      data: AppTheme.teacherTheme(),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.teacherBackground,
        body: _buildLoadingView(),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.teacherBackground,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.teacherBackground,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDashboardView(),
              TeacherClassroomScreen(
                teacher: widget.user,
                selectedClass: _selectedClass,
                classes: _classes,
                onClassChanged: (c) => setState(() => _selectedClass = c),
              ),
              TeacherLibraryScreen(teacher: widget.user),
              TeacherSettingsScreen(user: widget.user),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ============================================
  // DASHBOARD VIEW
  // ============================================

  Widget _buildDashboardView() {
    if (_selectedClass == null) {
      return const Center(child: Text('No class selected'));
    }

    return TeacherDashboardView(
      user: widget.user,
      selectedClass: _selectedClass!,
      classes: _classes,
      onClassChanged: (c) => setState(() => _selectedClass = c),
      onTabChanged: (index) => setState(() => _selectedIndex = index),
    );
  }

  // ============================================
  // LOADING VIEW
  // ============================================

  Widget _buildLoadingView() {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          children: [
            // Hero skeleton
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: BoxDecoration(
                gradient: AppColors.teacherGradient,
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusXL),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LumiSkeleton(width: 200, height: 24),
                  SizedBox(height: 6),
                  LumiSkeleton(width: 140, height: 14),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      LumiSkeleton(width: 80, height: 36, borderRadius: 20),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Engagement card skeleton
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius:
                    BorderRadius.circular(TeacherDimensions.radiusXL),
                border: Border.all(color: AppColors.teacherBorder),
              ),
              child: Row(
                children: [
                  const LumiSkeleton(
                      width: 100, height: 100, borderRadius: 50),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        LumiSkeleton(width: 120, height: 16),
                        SizedBox(height: 14),
                        LumiSkeleton(width: 80, height: 16),
                        SizedBox(height: 14),
                        LumiSkeleton(width: 100, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Chart skeleton
            const LumiSkeleton(
              height: 240,
              borderRadius: 24,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // BOTTOM NAVIGATION BAR
  // ============================================

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppColors.teacherPrimary.withValues(alpha: 0.12),
            blurRadius: 24,
            spreadRadius: -10,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: _onTabTapped,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            backgroundColor: AppColors.white,
            selectedItemColor: AppColors.teacherPrimary,
            unselectedItemColor: AppColors.textSecondary,
            selectedLabelStyle: TeacherTypography.caption.copyWith(
              color: AppColors.teacherPrimary,
            ),
            unselectedLabelStyle: TeacherTypography.caption,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                activeIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined),
                activeIcon: Icon(Icons.groups_rounded),
                label: 'Class',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_outlined),
                activeIcon: Icon(Icons.menu_book_rounded),
                label: 'Library',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined),
                activeIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // NO CLASSES VIEW
  // ============================================

  Widget _buildNoClassesView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _handleSignOut,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back, color: AppColors.charcoal),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: AppColors.teacherBorder),
                    boxShadow: TeacherDimensions.cardShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: AppColors.teacherSurfaceTint,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Center(
                          child: LumiMascot(
                            mood: LumiMood.thinking,
                            size: 66,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No Classes Assigned',
                        style: TeacherTypography.h1,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your dashboard is ready, but you need an active class before classroom and library workflows become useful.',
                        style: TeacherTypography.bodyLarge.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ask your school administrator to assign you to a class, then refresh here.',
                        style: TeacherTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 28),
                      LumiPrimaryButton(
                        onPressed: _loadClasses,
                        text: 'Refresh Classes',
                        color: AppColors.teacherPrimary,
                        isFullWidth: true,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
