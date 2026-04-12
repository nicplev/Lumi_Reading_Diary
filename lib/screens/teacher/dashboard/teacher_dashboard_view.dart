import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../data/models/achievement_model.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/reading_group_model.dart';
import '../../../data/models/reading_log_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/firebase_service.dart';
import 'models/student_achievement.dart';
import 'models/dashboard_widget_config.dart';
import 'models/dashboard_widget_context.dart';
import 'models/widget_registry.dart';
import 'widgets/edit_mode_wrapper.dart';
import 'widgets/widget_gallery_sheet.dart';

/// Teacher Dashboard View
///
/// Assembles all dashboard sections: hero, engagement card,
/// weekly chart, and priority nudges.
/// Supports Apple-style widget customisation — teachers can enter
/// edit mode to add, remove, and reorder widgets.
class TeacherDashboardView extends StatefulWidget {
  final UserModel user;
  final ClassModel selectedClass;
  final List<ClassModel> classes;
  final ValueChanged<ClassModel> onClassChanged;
  final ValueChanged<int> onTabChanged;
  final int resetTrigger;

  const TeacherDashboardView({
    super.key,
    required this.user,
    required this.selectedClass,
    required this.classes,
    required this.onClassChanged,
    required this.onTabChanged,
    this.resetTrigger = 0,
  });

  @override
  State<TeacherDashboardView> createState() => _TeacherDashboardViewState();
}

class _TeacherDashboardViewState extends State<TeacherDashboardView> {
  int _bellAnimCount = 0;
  String? _dailyInsight;
  int? _momentumDiff; // positive = up, negative = down
  List<StudentModel> _students = [];
  bool _studentsLoaded = false;
  List<ReadingLogModel> _weeklyLogs = [];
  bool _weeklyLogsLoaded = false;
  List<ReadingGroupModel> _readingGroups = [];
  bool _readingGroupsLoaded = false;
  StreamSubscription<QuerySnapshot>? _readingGroupsSubscription;
  List<StudentAchievement> _recentAchievements = [];
  final ValueNotifier<int> _engagementResetSignal = ValueNotifier<int>(0);

  // Widget customisation
  late DashboardWidgetConfig _widgetConfig;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    _widgetConfig =
        DashboardWidgetConfig.fromPreferences(widget.user.preferences);
    _computeHeroIntelligence();
    _fetchAllDependencies();
  }

  @override
  void dispose() {
    _readingGroupsSubscription?.cancel();
    _engagementResetSignal.dispose();
    super.dispose();
  }

  void resetEngagementCard() {
    _engagementResetSignal.value++;
  }

  @override
  void didUpdateWidget(TeacherDashboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedClass.id != widget.selectedClass.id) {
      _computeHeroIntelligence();
      _fetchAllDependencies();
    }
    if (oldWidget.resetTrigger != widget.resetTrigger) {
      resetEngagementCard();
    }
  }

  // ------------------------------------------------------------------
  // Widget config helpers
  // ------------------------------------------------------------------

  bool _anyWidgetNeeds(WidgetDataDependency dep) =>
      _widgetConfig.activeWidgetIds
          .map((id) => DashboardWidgetRegistry.get(id))
          .whereType<DashboardWidgetDefinition>()
          .any((w) => w.dataDependencies.contains(dep));

  bool get _anyWidgetNeedsStudents =>
      _anyWidgetNeeds(WidgetDataDependency.students);
  bool get _anyWidgetNeedsWeeklyLogs =>
      _anyWidgetNeeds(WidgetDataDependency.weeklyLogs);
  bool get _anyWidgetNeedsReadingGroups =>
      _anyWidgetNeeds(WidgetDataDependency.readingGroups);

  DashboardWidgetContext get _widgetContext => DashboardWidgetContext(
        classModel: widget.selectedClass,
        schoolId: widget.user.schoolId!,
        teacher: widget.user,
        students: _students,
        studentsLoaded: _studentsLoaded,
        engagementResetSignal: _engagementResetSignal,
        onViewAllReading: () => widget.onTabChanged(1),
        weeklyLogs: _weeklyLogs,
        weeklyLogsLoaded: _weeklyLogsLoaded,
        readingGroups: _readingGroups,
        readingGroupsLoaded: _readingGroupsLoaded,
        recentAchievements: _recentAchievements,
      );

  void _enterEditMode() {
    HapticFeedback.mediumImpact();
    setState(() => _isEditMode = true);
  }

  void _exitEditMode() {
    setState(() => _isEditMode = false);
    _saveWidgetConfig();
  }

  void _removeWidget(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      _widgetConfig = _widgetConfig.removeWidget(id);
    });
    if (!_anyWidgetNeedsStudents) _students = [];
    if (!_anyWidgetNeedsWeeklyLogs) _weeklyLogs = [];
    if (!_anyWidgetNeedsReadingGroups) {
      _readingGroupsSubscription?.cancel();
      _readingGroupsSubscription = null;
      _readingGroups = [];
    }
  }

  void _addWidget(String id) {
    HapticFeedback.lightImpact();
    final def = DashboardWidgetRegistry.get(id);
    final neededBefore = {
      WidgetDataDependency.students: _anyWidgetNeedsStudents,
      WidgetDataDependency.weeklyLogs: _anyWidgetNeedsWeeklyLogs,
      WidgetDataDependency.readingGroups: _anyWidgetNeedsReadingGroups,
    };
    setState(() {
      _widgetConfig = _widgetConfig.addWidget(id);
    });
    if (def == null) return;
    // Fetch any dependencies the new widget introduces
    if (!neededBefore[WidgetDataDependency.students]! &&
        def.dataDependencies.contains(WidgetDataDependency.students)) {
      _studentsLoaded = false;
      _fetchStudents();
    }
    if (!neededBefore[WidgetDataDependency.weeklyLogs]! &&
        def.dataDependencies.contains(WidgetDataDependency.weeklyLogs)) {
      _weeklyLogsLoaded = false;
      _fetchWeeklyLogs();
    }
    if (!neededBefore[WidgetDataDependency.readingGroups]! &&
        def.dataDependencies.contains(WidgetDataDependency.readingGroups)) {
      _readingGroupsLoaded = false;
      _fetchReadingGroups();
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      _widgetConfig = _widgetConfig.reorder(oldIndex, newIndex);
    });
  }

  void _showWidgetGallery() {
    final inactive =
        DashboardWidgetRegistry.getInactive(_widgetConfig.activeWidgetIds);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => WidgetGallerySheet(
        availableWidgets: inactive,
        onAddWidget: (id) {
          Navigator.pop(context);
          _addWidget(id);
        },
      ),
    );
  }

  Future<void> _saveWidgetConfig() async {
    try {
      final prefs =
          Map<String, dynamic>.from(widget.user.preferences ?? {});
      prefs.addAll(_widgetConfig.toPreferencesMap());

      await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.user.schoolId)
          .collection('users')
          .doc(widget.user.id)
          .update({'preferences': prefs});
    } catch (e) {
      debugPrint('Error saving dashboard widget config: $e');
    }
  }

  // ------------------------------------------------------------------
  // Data fetching
  // ------------------------------------------------------------------

  /// Launches all required fetches in parallel based on active widget deps.
  void _fetchAllDependencies() {
    if (_anyWidgetNeedsStudents) {
      _fetchStudents();
    } else {
      _studentsLoaded = true;
    }
    if (_anyWidgetNeedsWeeklyLogs) {
      _fetchWeeklyLogs();
    } else {
      _weeklyLogsLoaded = true;
    }
    if (_anyWidgetNeedsReadingGroups) {
      _fetchReadingGroups();
    } else {
      _readingGroupsLoaded = true;
    }
  }

  Future<void> _fetchStudents() async {
    final studentIds = widget.selectedClass.studentIds;
    final schoolId = widget.user.schoolId;
    if (studentIds.isEmpty || schoolId == null) {
      if (mounted) setState(() {
        _students = [];
        _recentAchievements = [];
        _studentsLoaded = true;
      });
      return;
    }

    try {
      final List<StudentModel> students = [];
      final List<StudentAchievement> achievements = [];
      // Batch in groups of 30 (Firestore whereIn limit)
      for (var i = 0; i < studentIds.length; i += 30) {
        final batch = studentIds.sublist(
          i,
          i + 30 > studentIds.length ? studentIds.length : i + 30,
        );
        final snapshot = await FirebaseService.instance.firestore
            .collection('schools')
            .doc(schoolId)
            .collection('students')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snapshot.docs) {
          students.add(StudentModel.fromFirestore(doc));
          // Extract achievements from raw doc (piggyback — zero extra reads)
          final data = doc.data();
          final achievementsData =
              data['achievements'] as List<dynamic>? ?? [];
          final firstName = (data['firstName'] as String?) ?? '';
          for (final a in achievementsData) {
            try {
              achievements.add(StudentAchievement(
                studentId: doc.id,
                studentFirstName: firstName,
                achievement:
                    AchievementModel.fromMap(Map<String, dynamic>.from(a)),
              ));
            } catch (_) {
              // Skip malformed achievements
            }
          }
        }
      }
      // Sort achievements newest-first
      achievements.sort(
          (a, b) => b.achievement.earnedAt.compareTo(a.achievement.earnedAt));

      if (!mounted) return;
      setState(() {
        _students = students;
        _recentAchievements = achievements;
        _studentsLoaded = true;
      });
    } catch (e) {
      debugPrint('Error fetching students for dashboard: $e');
      if (mounted) setState(() => _studentsLoaded = true);
    }
  }

  Future<void> _fetchWeeklyLogs() async {
    final schoolId = widget.user.schoolId;
    if (schoolId == null) {
      if (mounted) setState(() { _weeklyLogs = []; _weeklyLogsLoaded = true; });
      return;
    }

    try {
      final now = DateTime.now();
      final startOfWeek =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));

      final snapshot = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.selectedClass.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .get();

      if (!mounted) return;
      setState(() {
        _weeklyLogs = snapshot.docs
            .map((doc) => ReadingLogModel.fromFirestore(doc))
            .toList();
        _weeklyLogsLoaded = true;
      });
    } catch (e) {
      debugPrint('Error fetching weekly logs for dashboard: $e');
      if (mounted) setState(() => _weeklyLogsLoaded = true);
    }
  }

  void _fetchReadingGroups() {
    _readingGroupsSubscription?.cancel();

    final schoolId = widget.user.schoolId;
    if (schoolId == null) {
      if (mounted) {
        setState(() {
          _readingGroups = [];
          _readingGroupsLoaded = true;
        });
      }
      return;
    }

    _readingGroupsSubscription = FirebaseService.instance.firestore
        .collection('schools')
        .doc(schoolId)
        .collection('readingGroups')
        .where('classId', isEqualTo: widget.selectedClass.id)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) return;
        final groups = snapshot.docs
            .map((doc) => ReadingGroupModel.fromFirestore(doc))
            .toList()
          ..sort((a, b) {
            final orderCmp = a.sortOrder.compareTo(b.sortOrder);
            return orderCmp != 0 ? orderCmp : a.name.compareTo(b.name);
          });
        setState(() {
          _readingGroups = groups;
          _readingGroupsLoaded = true;
        });
      },
      onError: (e) {
        debugPrint('Error fetching reading groups for dashboard: $e');
        if (mounted) setState(() => _readingGroupsLoaded = true);
      },
    );
  }

  Future<void> _computeHeroIntelligence() async {
    try {
      final schoolId = widget.user.schoolId;
      if (schoolId == null) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final totalStudents = widget.selectedClass.studentIds.length;

      // Fetch yesterday's logs for insight
      final yesterdayLogs = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.selectedClass.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday))
          .where('date', isLessThan: Timestamp.fromDate(today))
          .get();

      final yesterdayStudents =
          yesterdayLogs.docs.map((d) {
            final data = d.data();
            return data['studentId'] as String?;
          }).whereType<String>().toSet();

      String? insight;
      if (totalStudents > 0 && yesterdayStudents.length == totalStudents) {
        insight = 'Everyone read yesterday!';
      } else if (totalStudents > 0 && yesterdayStudents.isNotEmpty) {
        final pct =
            (yesterdayStudents.length / totalStudents * 100).round();
        insight =
            '$pct% of ${widget.selectedClass.name} read yesterday';
      }

      // Compute class streak + momentum with a single 30-day query
      final startOfWeek =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
      final thirtyDaysAgo = today.subtract(const Duration(days: 30));

      final recentLogs = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.selectedClass.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(thirtyDaysAgo))
          .get();

      // Build set of students per week for momentum
      final Set<String> thisWeekStudents = {};
      final Set<String> lastWeekStudents = {};

      for (final doc in recentLogs.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();

        final studentId = data['studentId'] as String?;
        if (studentId != null) {
          if (!date.isBefore(startOfWeek)) {
            thisWeekStudents.add(studentId);
          } else if (!date.isBefore(startOfLastWeek)) {
            lastWeekStudents.add(studentId);
          }
        }
      }

      int? momentum;
      if (totalStudents > 0 && lastWeekStudents.isNotEmpty) {
        final thisPercent =
            (thisWeekStudents.length / totalStudents * 100).round();
        final lastPercent =
            (lastWeekStudents.length / totalStudents * 100).round();
        final diff = thisPercent - lastPercent;
        if (diff.abs() >= 5) momentum = diff;
      }

      if (!mounted) return;
      setState(() {
        _dailyInsight = insight;
        _momentumDiff = momentum;
      });
    } catch (e) {
      debugPrint('Error computing hero intelligence: $e');
    }
  }

  // ------------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final ctx = _widgetContext;
    final activeDefinitions = _widgetConfig.activeWidgetIds
        .map((id) => DashboardWidgetRegistry.get(id))
        .whereType<DashboardWidgetDefinition>()
        .toList();

    return GestureDetector(
      onTap: _isEditMode ? null : resetEngagementCard,
      onLongPress: _isEditMode ? null : _enterEditMode,
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topPadding + 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildHero(),
            )
                .animate()
                .fadeIn(duration: 400.ms, curve: Curves.easeOut)
                .slideY(begin: -0.02, end: 0, duration: 400.ms),
          ),

          // ── Edit-mode banner ──
          if (_isEditMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildEditModeBanner(),
              ),
            ),

          // ── Widget cards ──
          if (_isEditMode)
            _buildEditableWidgetSliver(activeDefinitions, ctx)
          else
            _buildNormalWidgetSliver(activeDefinitions, ctx),

          // ── Customize link (normal mode only) ──
          if (!_isEditMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: GestureDetector(
                  onTap: _enterEditMode,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.dashboard_customize_rounded,
                          size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Customize dashboard',
                        style: TeacherTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Bottom padding ──
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Normal (non-edit) widget list
  // ------------------------------------------------------------------

  Widget _buildNormalWidgetSliver(
      List<DashboardWidgetDefinition> defs, DashboardWidgetContext ctx) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            // Interleave widgets with spacers: 0=widget, 1=space, 2=widget…
            if (index.isOdd) return const SizedBox(height: 24);
            final widgetIndex = index ~/ 2;
            final def = defs[widgetIndex];

            // Skip widgets whose shared data hasn't loaded yet
            if ((def.dataDependencies.contains(WidgetDataDependency.students) && !_studentsLoaded) ||
                (def.dataDependencies.contains(WidgetDataDependency.weeklyLogs) && !_weeklyLogsLoaded) ||
                (def.dataDependencies.contains(WidgetDataDependency.readingGroups) && !_readingGroupsLoaded)) {
              return const SizedBox.shrink();
            }

            return def
                .builder(ctx)
                .animate()
                .fadeIn(
                    delay: (60 * widgetIndex).ms,
                    duration: 300.ms,
                    curve: Curves.easeOut)
                .slideY(begin: 0.02, end: 0, duration: 300.ms);
          },
          childCount: defs.isEmpty ? 0 : defs.length * 2 - 1,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Edit-mode widget list (reorderable)
  // ------------------------------------------------------------------

  Widget _buildEditableWidgetSliver(
      List<DashboardWidgetDefinition> defs, DashboardWidgetContext ctx) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          children: [
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final scale = Tween<double>(begin: 1.0, end: 1.04)
                        .animate(CurvedAnimation(
                            parent: animation, curve: Curves.easeInOut));
                    return Transform.scale(
                      scale: scale.value,
                      child: child,
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.15),
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusXL),
                    child: child,
                  ),
                );
              },
              onReorder: _onReorder,
              itemCount: defs.length,
              itemBuilder: (context, index) {
                final def = defs[index];
                final needsStudents = def.dataDependencies
                    .contains(WidgetDataDependency.students);

                return Padding(
                  key: ValueKey(def.id),
                  padding: const EdgeInsets.only(bottom: 20),
                  child: EditModeWrapper(
                    onRemove: () => _removeWidget(def.id),
                    child: (needsStudents && !_studentsLoaded)
                        ? _buildWidgetPlaceholder(def)
                        : def.builder(ctx),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            _buildAddWidgetButton(),
            const SizedBox(height: 16),
            _buildDoneButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildWidgetPlaceholder(DashboardWidgetDefinition def) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: AppColors.teacherBackground,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, size: 24, color: AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(def.displayName,
                style: TeacherTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Edit-mode UI elements
  // ------------------------------------------------------------------

  Widget _buildEditModeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.teacherSurfaceTint,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        border: Border.all(
            color: AppColors.teacherPrimary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.widgets_rounded,
              size: 18, color: AppColors.teacherPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Customise your dashboard',
              style: TeacherTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.teacherPrimary,
              ),
            ),
          ),
          Text(
            'Drag to reorder',
            style: TeacherTypography.caption
                .copyWith(color: AppColors.teacherPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildAddWidgetButton() {
    final inactiveCount = DashboardWidgetRegistry.getInactive(
            _widgetConfig.activeWidgetIds)
        .length;

    return GestureDetector(
      onTap: _showWidgetGallery,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.teacherPrimary.withValues(alpha: 0.35),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          color: AppColors.teacherSurfaceTint.withValues(alpha: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 20, color: AppColors.teacherPrimary),
            const SizedBox(width: 8),
            Text(
              inactiveCount > 0
                  ? 'Add Widget ($inactiveCount available)'
                  : 'All Widgets Active',
              style: TeacherTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.teacherPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _exitEditMode,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.teacherPrimary,
          foregroundColor: AppColors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          ),
          elevation: 0,
        ),
        child: Text('Done', style: TeacherTypography.buttonText),
      ),
    );
  }

  // ============================================
  // HERO SECTION
  // ============================================

  Widget _buildHero() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';
    final firstName = widget.user.fullName.isNotEmpty
        ? widget.user.fullName.split(' ').first
        : 'Teacher';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        gradient: AppColors.teacherGradient,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -20,
            top: -30,
            child: CustomPaint(
              size: const Size(140, 140),
              painter: _DecorativeCirclesPainter(),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting, $firstName',
                          style: TeacherTypography.h2.copyWith(
                            color: AppColors.white,
                          ),
                        ).animate().fadeIn(duration: 400.ms).slideY(
                              begin: -0.1,
                              end: 0,
                              duration: 400.ms,
                              curve: Curves.easeOut,
                            ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEEE, MMMM d').format(DateTime.now()),
                          style: TeacherTypography.bodyMedium.copyWith(
                            color: AppColors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        if (_dailyInsight != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _dailyInsight!,
                            style: TeacherTypography.bodySmall.copyWith(
                              color:
                                  AppColors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  _buildBellButton(context),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildClassChip()
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 300.ms),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildClassChip() {
    final label = widget.selectedClass.name;

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.class_outlined, size: 18, color: AppColors.white),
        const SizedBox(width: 8),
        Text(
          label,
          style: TeacherTypography.bodyMedium.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_momentumDiff != null) ...[
          const SizedBox(width: 6),
          Icon(
            _momentumDiff! > 0
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 16,
            color: _momentumDiff! > 0
                ? const Color(0xFFB9F6CA)
                : const Color(0xFFFFCDD2),
          ),
        ],
        if (widget.classes.length > 1) ...[
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down,
              size: 18, color: AppColors.white),
        ],
      ],
    );

    // Single class: render as plain label (no pill, no tap handler)
    if (widget.classes.length <= 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: labelRow,
      );
    }

    // Multiple classes: interactive pill with dropdown affordance
    return Material(
      color: AppColors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => _showClassSelectorBottomSheet(context),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showClassSelectorBottomSheet(context);
        },
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: labelRow,
        ),
      ),
    );
  }


  Widget _buildBellButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _bellAnimCount++);
        final nav = GoRouter.of(context);
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            nav.push('/teacher/notifications', extra: widget.user);
          }
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child:
            const Icon(Icons.notifications_outlined, size: 20, color: AppColors.white)
                .animate(
                    key: ValueKey(_bellAnimCount),
                    autoPlay: _bellAnimCount > 0)
                .scale(
                  begin: const Offset(1.0, 1.0),
                  end: const Offset(1.18, 1.18),
                  duration: 200.ms,
                  curve: Curves.easeOut,
                )
                .then()
                .scale(
                  begin: const Offset(1.18, 1.18),
                  end: const Offset(1.0, 1.0),
                  duration: 200.ms,
                  curve: Curves.easeIn,
                )
                .shake(duration: 350.ms, hz: 4, rotation: 0.05),
      ),
    );
  }

  void _showClassSelectorBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 20),
            Text('Select Class', style: TeacherTypography.h3),
            const SizedBox(height: 18),
            ...widget.classes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: widget.selectedClass.id == c.id
                      ? AppColors.teacherSurfaceTint
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: widget.selectedClass.id == c.id
                            ? AppColors.teacherPrimary
                                .withValues(alpha: 0.18)
                            : AppColors.teacherBorder,
                      ),
                    ),
                    title: Text(
                      c.name,
                      style: TeacherTypography.bodyLarge.copyWith(
                        fontWeight: widget.selectedClass.id == c.id
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: widget.selectedClass.id == c.id
                            ? AppColors.teacherPrimary
                            : AppColors.charcoal,
                      ),
                    ),
                    subtitle: Text(
                      '${c.studentIds.length} students',
                      style: TeacherTypography.bodySmall,
                    ),
                    trailing: widget.selectedClass.id == c.id
                        ? Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.teacherPrimary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.check,
                                size: 18, color: AppColors.white),
                          )
                        : null,
                    onTap: () {
                      widget.onClassChanged(c);
                      Navigator.pop(context);
                    },
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

/// Decorative overlapping circles for the hero section.
class _DecorativeCirclesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.3), 60, paint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.6), 80, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
