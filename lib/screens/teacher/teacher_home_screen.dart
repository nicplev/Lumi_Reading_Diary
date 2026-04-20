import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rive/rive.dart' hide Animation;

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

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  int _selectedIndex = 0;
  int _dashboardResetTrigger = 0;
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  bool _isLoading = true;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    _pageController = PageController();

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
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
      _dashboardResetTrigger++;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
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
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) => setState(() {
          _selectedIndex = index;
          _dashboardResetTrigger++;
        }),
        children: [
          _KeepAlivePage(child: _buildDashboardView()),
          _KeepAlivePage(
            child: TeacherClassroomScreen(
              teacher: widget.user,
              selectedClass: _selectedClass,
              classes: _classes,
              onClassChanged: (c) => setState(() => _selectedClass = c),
            ),
          ),
          _KeepAlivePage(child: TeacherLibraryScreen(teacher: widget.user)),
          _KeepAlivePage(child: TeacherSettingsScreen(user: widget.user)),
        ],
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
      onTabChanged: (index) {
        setState(() => _selectedIndex = index);
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      resetTrigger: _dashboardResetTrigger,
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
    const navItems = [
      ('assets/animations/nav_dashboard.riv', 'Dashboard'),
      ('assets/animations/nav_class.riv', 'Class'),
      ('assets/animations/nav_library.riv', 'Library'),
      ('assets/animations/nav_settings.riv', 'Settings'),
    ];

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
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              for (int i = 0; i < navItems.length; i++)
                Expanded(
                  child: _RiveNavItem(
                    assetPath: navItems[i].$1,
                    label: navItems[i].$2,
                    isSelected: _selectedIndex == i,
                    onTap: () => _onTabTapped(i),
                    selectedColor: AppColors.teacherPrimary,
                    unselectedColor: AppColors.textSecondary,
                  ),
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
                            variant: LumiVariant.teacher,
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

class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// Custom controller that plays nav animations when triggered.
// Files with 'Timeline 1' are driven directly; files using a state machine
// with an 'isActive' boolean input use that instead.
base class _NavRiveController extends RiveWidgetController {
  // Stored as dynamic to avoid the Animation name conflict between
  // Flutter's Animation<T> and rive_native's Animation class.
  static const double _speed = 2.5;

  dynamic _animation;
  dynamic _isActiveInput; // BooleanInput for state-machine-based .riv files
  bool _playing = false;

  _NavRiveController(super.file) {
    _animation = artboard.animationNamed('Timeline 1');
    if (_animation == null) {
      // Fall back to driving via the state machine's isActive boolean input.
      // ignore: deprecated_member_use
      _isActiveInput = stateMachine.boolean('isActive');
    }
  }

  void play() {
    if (_animation != null) {
      _animation.time = 0.0;
      _playing = true;
      scheduleRepaint();
    } else if (_isActiveInput != null) {
      _isActiveInput.value = true;
      scheduleRepaint();
    }
  }

  void deactivate() {
    if (_isActiveInput != null) {
      _isActiveInput.value = false;
      scheduleRepaint();
    }
  }

  @override
  bool advance(double elapsedSeconds) {
    final scaled = elapsedSeconds * _speed;
    final smNeedsMore = super.advance(scaled);
    if (_playing && _animation != null) {
      final bool stillGoing = _animation.advanceAndApply(scaled);
      if (!stillGoing) _playing = false;
      return smNeedsMore || stillGoing;
    }
    return smNeedsMore;
  }
}

class _RiveNavItem extends StatefulWidget {
  final String assetPath;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color unselectedColor;

  const _RiveNavItem({
    required this.assetPath,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.selectedColor,
    required this.unselectedColor,
  });

  @override
  State<_RiveNavItem> createState() => _RiveNavItemState();
}

class _RiveNavItemState extends State<_RiveNavItem> {
  late final FileLoader _fileLoader;
  _NavRiveController? _riveController;

  @override
  void initState() {
    super.initState();
    _fileLoader = FileLoader.fromAsset(
      widget.assetPath,
      riveFactory: Factory.flutter,
    );
  }

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  void _onLoaded(RiveLoaded state) {
    _riveController = state.controller as _NavRiveController;
    if (widget.isSelected) _riveController!.play();
  }

  @override
  void didUpdateWidget(_RiveNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected && !widget.isSelected) {
      _riveController?.deactivate();
    }
    if (!oldWidget.isSelected && widget.isSelected) {
      _riveController?.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: RiveWidgetBuilder(
              fileLoader: _fileLoader,
              controller: (file) => _NavRiveController(file),
              onLoaded: _onLoaded,
              builder: (context, state) => switch (state) {
                RiveLoaded() => RiveWidget(
                    controller: state.controller,
                    fit: Fit.contain,
                  ),
                _ => const SizedBox(),
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.label,
            style: TeacherTypography.caption.copyWith(
              color: widget.isSelected
                  ? widget.selectedColor
                  : widget.unselectedColor,
            ),
          ),
        ],
      ),
    );
  }
}
