import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rive/rive.dart' hide Animation;


import '../../core/theme/app_theme.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../core/widgets/lumi/lumi_skeleton.dart';
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
  bool _isProgrammaticPageChange = false;

  late final PageController _pageController;

  @override
  void initState() {
    super.initState();

    _pageController = PageController();

    // Role guard: redirect if user is not a teacher.
    if (widget.user.role != UserRole.teacher) {
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
    _isProgrammaticPageChange = true;
    _pageController
        .animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        )
        .whenComplete(() {
      if (mounted) _isProgrammaticPageChange = false;
    });
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
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      // Tell the teacher the load FAILED — otherwise a query error renders the
      // same "no classes" empty state as a genuinely class-less teacher, who
      // then assumes their classes vanished.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't load your classes. Please try again."),
        ),
      );
    }
  }

  Future<void> _handleSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign Out',
              style: LumiType.button.copyWith(color: LumiTokens.red),
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
        backgroundColor: LumiTokens.cream,
        body: _buildLoadingView(),
      );
    }

    if (_classes.isEmpty) {
      return Scaffold(
        backgroundColor: LumiTokens.cream,
        body: _buildNoClassesView(),
      );
    }

    return Scaffold(
      backgroundColor: LumiTokens.cream,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              if (_isProgrammaticPageChange) return;
              setState(() {
                _selectedIndex = index;
                _dashboardResetTrigger++;
              });
            },
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
          Positioned(
            left: 16,
            right: 16,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 8),
              child: _buildBottomNavigationBar(),
            ),
          ),
        ],
      ),
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
                color: LumiTokens.blue,
                borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
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
                color: LumiTokens.paper,
                borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
                border: Border.all(color: LumiTokens.rule),
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
    final navItems = <_NavItemSpec>[
      const _NavItemSpec.rive(
        assetPath: 'assets/animations/nav_dashboard.riv',
        label: 'Dashboard',
      ),
      const _NavItemSpec.icon(
        icon: Icons.groups_outlined,
        label: 'Class',
        size: 27,
      ),
      const _NavItemSpec.icon(icon: Icons.book_outlined, label: 'Library'),
      const _NavItemSpec.icon(icon: Icons.settings_outlined, label: 'Settings'),
    ];

    // Active tab adopts its section's colour:
    // Dashboard = blue, Class = green, Library = yellow, Settings = red.
    const sectionColors = [
      LumiTokens.blue,
      LumiTokens.green,
      LumiTokens.yellow,
      LumiTokens.red,
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: LumiTokens.ink.withValues(alpha: 0.08),
            blurRadius: 28,
            spreadRadius: -8,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            spreadRadius: -6,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: LumiTokens.paper.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(36),
              border: Border.all(
                color: LumiTokens.paper.withValues(alpha: 0.55),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
            children: [
              for (int i = 0; i < navItems.length; i++)
                Expanded(
                  child: switch (navItems[i]) {
                    _RiveNavSpec(:final assetPath, :final label) => _RiveNavItem(
                        assetPath: assetPath,
                        label: label,
                        isSelected: _selectedIndex == i,
                        onTap: () => _onTabTapped(i),
                        selectedColor: sectionColors[i],
                        unselectedColor: LumiTokens.muted,
                      ),
                    _IconNavSpec(:final icon, :final label, :final size) =>
                      _IconNavItem(
                        icon: icon,
                        label: label,
                        size: size,
                        isSelected: _selectedIndex == i,
                        onTap: () => _onTabTapped(i),
                        selectedColor: sectionColors[i],
                        unselectedColor: LumiTokens.muted,
                      ),
                  },
                ),
            ],
          ),
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
                color: LumiTokens.paper,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: _handleSignOut,
                  borderRadius: BorderRadius.circular(16),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.arrow_back, color: LumiTokens.ink),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: LumiTokens.paper,
                    borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
                    border: Border.all(color: LumiTokens.rule),
                    boxShadow: LumiTokens.shadowCard,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/UI Lumi/lumi welcome.png',
                        height: 150,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No Classes Assigned',
                        style: LumiType.subhead,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your dashboard is ready, but you need an active class before classroom and library workflows become useful.',
                        style: LumiType.body.copyWith(
                          color: LumiTokens.muted,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Ask your school administrator to assign you to a class, then refresh here.',
                        style: LumiType.body.copyWith(
                          color: LumiTokens.muted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _loadClasses,
                          style: FilledButton.styleFrom(
                            backgroundColor: LumiTokens.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(LumiTokens.radiusLarge),
                            ),
                          ),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(
                            'Refresh Classes',
                            style: LumiType.button
                                .copyWith(color: Colors.white),
                          ),
                        ),
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

sealed class _NavItemSpec {
  const _NavItemSpec();

  const factory _NavItemSpec.rive({
    required String assetPath,
    required String label,
  }) = _RiveNavSpec;

  const factory _NavItemSpec.icon({
    required IconData icon,
    required String label,
    double size,
  }) = _IconNavSpec;
}

final class _RiveNavSpec extends _NavItemSpec {
  final String assetPath;
  final String label;
  const _RiveNavSpec({required this.assetPath, required this.label});
}

final class _IconNavSpec extends _NavItemSpec {
  final IconData icon;
  final String label;
  final double size;
  const _IconNavSpec({
    required this.icon,
    required this.label,
    this.size = 24,
  });
}

class _IconNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final double size;
  final bool isSelected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color unselectedColor;

  const _IconNavItem({
    required this.icon,
    required this.label,
    required this.size,
    required this.isSelected,
    required this.onTap,
    required this.selectedColor,
    required this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? selectedColor : unselectedColor;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(icon, size: size, color: color),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: LumiType.caption.copyWith(color: color),
          ),
        ],
      ),
    );
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
            width: 28,
            height: 28,
            child: ClipRect(
              child: OverflowBox(
                minWidth: 40,
                maxWidth: 40,
                minHeight: 40,
                maxHeight: 40,
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
            ),
          ),
          const SizedBox(height: 1),
          Text(
            widget.label,
            style: LumiType.caption.copyWith(
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
