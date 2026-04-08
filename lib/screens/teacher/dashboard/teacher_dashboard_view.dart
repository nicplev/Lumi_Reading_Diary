import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../data/models/class_model.dart';
import '../../../data/models/student_model.dart';
import '../../../data/models/user_model.dart';
import '../../../services/firebase_service.dart';
import 'widgets/dashboard_engagement_card.dart';
import 'widgets/dashboard_recent_reading_card.dart';
import 'widgets/dashboard_weekly_chart.dart';
import 'widgets/dashboard_priority_nudges.dart';

/// Teacher Dashboard View
///
/// Assembles all dashboard sections: hero, engagement card,
/// weekly chart, and priority nudges.
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
  int? _classStreakDays;
  int? _momentumDiff; // positive = up, negative = down
  List<StudentModel> _students = [];
  bool _studentsLoaded = false;
  final ValueNotifier<int> _engagementResetSignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _computeHeroIntelligence();
    _fetchStudents();
  }

  @override
  void dispose() {
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
      _fetchStudents();
    }
    if (oldWidget.resetTrigger != widget.resetTrigger) {
      resetEngagementCard();
    }
  }

  Future<void> _fetchStudents() async {
    final studentIds = widget.selectedClass.studentIds;
    final schoolId = widget.user.schoolId;
    if (studentIds.isEmpty || schoolId == null) {
      if (mounted) setState(() { _students = []; _studentsLoaded = true; });
      return;
    }

    try {
      final List<StudentModel> students = [];
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
        }
      }
      if (!mounted) return;
      setState(() { _students = students; _studentsLoaded = true; });
    } catch (e) {
      debugPrint('Error fetching students for dashboard: $e');
      if (mounted) setState(() => _studentsLoaded = true);
    }
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

      // Build set of dates that had at least one log
      final Set<String> daysWithLogs = {};
      final Set<String> thisWeekStudents = {};
      final Set<String> lastWeekStudents = {};

      for (final doc in recentLogs.docs) {
        final data = doc.data();
        final date = (data['date'] as Timestamp).toDate();
        final dateKey =
            '${date.year}-${date.month}-${date.day}';
        daysWithLogs.add(dateKey);

        final studentId = data['studentId'] as String?;
        if (studentId != null) {
          if (!date.isBefore(startOfWeek)) {
            thisWeekStudents.add(studentId);
          } else if (!date.isBefore(startOfLastWeek)) {
            lastWeekStudents.add(studentId);
          }
        }
      }

      // Compute streak: consecutive days going back from yesterday
      int streakDays = 0;
      for (int i = 1; i <= 30; i++) {
        final checkDate = today.subtract(Duration(days: i));
        final key =
            '${checkDate.year}-${checkDate.month}-${checkDate.day}';
        if (daysWithLogs.contains(key)) {
          streakDays++;
        } else {
          break;
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
        _classStreakDays = streakDays >= 2 ? streakDays : null;
        _momentumDiff = momentum;
      });
    } catch (e) {
      debugPrint('Error computing hero intelligence: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return GestureDetector(
      onTap: resetEngagementCard,
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Engagement Card
                DashboardEngagementCard(
                  classModel: widget.selectedClass,
                  schoolId: widget.user.schoolId!,
                  students: _students,
                  resetSignal: _engagementResetSignal,
                )
                    .animate()
                    .fadeIn(
                        delay: 60.ms,
                        duration: 300.ms,
                        curve: Curves.easeOut)
                    .slideY(begin: 0.02, end: 0, duration: 300.ms),
                const SizedBox(height: 24),
                // Recent Reading
                if (_studentsLoaded)
                  DashboardRecentReadingCard(
                    classModel: widget.selectedClass,
                    schoolId: widget.user.schoolId!,
                    students: _students,
                    onViewAll: () => widget.onTabChanged(1),
                  )
                      .animate()
                      .fadeIn(
                          delay: 90.ms,
                          duration: 300.ms,
                          curve: Curves.easeOut)
                      .slideY(begin: 0.02, end: 0, duration: 300.ms),
                if (_studentsLoaded) const SizedBox(height: 24),
                // Weekly Chart
                DashboardWeeklyChart(
                  classModel: widget.selectedClass,
                  schoolId: widget.user.schoolId!,
                )
                    .animate()
                    .fadeIn(
                        delay: 120.ms,
                        duration: 300.ms,
                        curve: Curves.easeOut)
                    .slideY(begin: 0.02, end: 0, duration: 300.ms),
                const SizedBox(height: 24),
                // Priority Nudges
                if (_studentsLoaded)
                  DashboardPriorityNudges(
                    classModel: widget.selectedClass,
                    schoolId: widget.user.schoolId!,
                    teacher: widget.user,
                    students: _students,
                    onSeeAll: () => widget.onTabChanged(1),
                  )
                      .animate()
                      .fadeIn(
                          delay: 180.ms,
                          duration: 300.ms,
                          curve: Curves.easeOut)
                      .slideY(begin: 0.02, end: 0, duration: 300.ms),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
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
                  if (_classStreakDays != null) ...[
                    const SizedBox(width: 8),
                    _buildStreakPill(),
                  ],
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

    return Material(
      color: AppColors.white.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: widget.classes.length > 1
            ? () => _showClassSelectorBottomSheet(context)
            : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.class_outlined,
                  size: 18, color: AppColors.white),
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
          ),
        ),
      ),
    );
  }

  Widget _buildStreakPill() {
    final isGold = _classStreakDays! >= 7;
    final color = isGold ? const Color(0xFFFFD700) : AppColors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$_classStreakDays-day streak',
            style: TeacherTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
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
