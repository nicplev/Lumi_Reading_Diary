import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../core/widgets/lumi/animated_count_text.dart';
import '../../../../core/widgets/lumi/engagement_ring_painter.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../services/firebase_service.dart';

/// Dashboard Engagement Card
///
/// Two-column card: engagement ring (left) + 3 stat rows with fractions (right).
/// Shows today's reading engagement at a glance.
///
/// Accepts a shared [students] list from the parent to avoid duplicate
/// Firestore reads across dashboard widgets.
class DashboardEngagementCard extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;
  final List<StudentModel> students;
  final ValueNotifier<int>? resetSignal;

  const DashboardEngagementCard({
    super.key,
    required this.classModel,
    required this.schoolId,
    required this.students,
    this.resetSignal,
  });

  @override
  State<DashboardEngagementCard> createState() =>
      _DashboardEngagementCardState();
}

class _DashboardEngagementCardState extends State<DashboardEngagementCard>
    with SingleTickerProviderStateMixin {
  late Stream<QuerySnapshot> _logsStream;
  late AnimationController _flipController;
  late Animation<Offset> _statsSlide;
  late Animation<Offset> _listSlide;
  late Animation<double> _statsFade;
  late Animation<double> _listFade;
  final ScrollController _pendingScrollController = ScrollController();
  bool _showingPending = false;

  void _onResetSignal() {
    if (_showingPending) {
      _showingPending = false;
      _flipController.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _initStream();
    widget.resetSignal?.addListener(_onResetSignal);
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _statsSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1, 0),
    ).animate(CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOut,
    ));
    _listSlide = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _flipController,
      curve: Curves.easeInOut,
    ));
    _statsFade = Tween<double>(begin: 1, end: 0).animate(CurvedAnimation(
      parent: _flipController,
      curve: const Interval(0, 0.5),
    ));
    _listFade = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _flipController,
      curve: const Interval(0.3, 1),
    ));
  }

  @override
  void dispose() {
    widget.resetSignal?.removeListener(_onResetSignal);
    _flipController.dispose();
    _pendingScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DashboardEngagementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetSignal != widget.resetSignal) {
      oldWidget.resetSignal?.removeListener(_onResetSignal);
      widget.resetSignal?.addListener(_onResetSignal);
    }
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
      if (_showingPending) {
        _flipController.reverse();
        _showingPending = false;
      }
    }
  }

  void _initStream() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    _logsStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(endOfDay))
        .snapshots();
  }

  void _togglePendingView() {
    setState(() => _showingPending = !_showingPending);
    if (_showingPending) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalStudents = widget.classModel.studentIds.length;

    return StreamBuilder<QuerySnapshot>(
      stream: _logsStream,
      builder: (context, logsSnapshot) {
        final logs = logsSnapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        final uniqueStudentsToday = logs.map((l) => l.studentId).toSet();
        final readCount = uniqueStudentsToday.length;
        final totalMinutes =
            logs.fold<int>(0, (total, log) => total + log.minutesRead);

        // Compute streak count from shared students data
        int onStreakCount = 0;
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final yesterday = today.subtract(const Duration(days: 1));

        for (final student in widget.students) {
          final stats = student.stats;
          if (stats == null || stats.currentStreak <= 0) continue;
          final lastRead = stats.lastReadingDate;
          if (lastRead == null) continue;
          final lastDay = DateTime(
            lastRead.year,
            lastRead.month,
            lastRead.day,
          );
          if (lastDay.isAtSameMomentAs(today) ||
              lastDay.isAtSameMomentAs(yesterday)) {
            onStreakCount++;
          }
        }

        final notReadCount = totalStudents - readCount;
        final engagementPercent = totalStudents > 0
            ? (readCount / totalStudents * 100).round()
            : 0;
        final isAllRead = totalStudents > 0 && readCount >= totalStudents;

        final pendingStudents = widget.students
            .where((s) => !uniqueStudentsToday.contains(s.id))
            .toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));

        return Container(
          padding: const EdgeInsets.all(20),
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius:
                BorderRadius.circular(TeacherDimensions.radiusXL),
            border: Border.all(
              color: isAllRead
                  ? AppColors.success.withValues(alpha: 0.2)
                  : AppColors.teacherBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.charcoal.withValues(alpha: 0.04),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _flipController,
            builder: (context, _) {
              return Stack(
                children: [
                  // Stats view (slides out left)
                  SlideTransition(
                    position: _statsSlide,
                    child: FadeTransition(
                      opacity: _statsFade,
                      child: _buildEngagementContent(
                        readCount: readCount,
                        totalStudents: totalStudents,
                        notReadCount: notReadCount,
                        onStreakCount: onStreakCount,
                        engagementPercent: engagementPercent,
                        isAllRead: isAllRead,
                        totalMinutes: totalMinutes,
                      ),
                    ),
                  ),
                  // Pending list (slides in from right)
                  if (_flipController.value > 0)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _togglePendingView,
                        behavior: HitTestBehavior.opaque,
                        child: SlideTransition(
                          position: _listSlide,
                          child: FadeTransition(
                            opacity: _listFade,
                            child: _buildPendingList(pendingStudents),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPendingList(List<StudentModel> pendingStudents) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: _togglePendingView,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Icon(Icons.schedule_rounded,
                size: 16, color: AppColors.warmOrange),
            const SizedBox(width: 6),
            Text(
              '${pendingStudents.length} haven\'t read yet',
              style: TeacherTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Scrollbar(
            controller: _pendingScrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _pendingScrollController,
              padding: const EdgeInsets.only(right: 8),
              itemCount: pendingStudents.length,
              itemBuilder: (context, index) {
                final student = pendingStudents[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.teacherSurfaceTint,
                        child: Text(
                          student.firstName.isNotEmpty
                              ? student.firstName[0].toUpperCase()
                              : '?',
                          style: TeacherTypography.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.teacherPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          student.fullName,
                          style: TeacherTypography.bodySmall.copyWith(
                            color: AppColors.charcoal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEngagementContent({
    required int readCount,
    required int totalStudents,
    required int notReadCount,
    required int onStreakCount,
    required int engagementPercent,
    required bool isAllRead,
    required int totalMinutes,
  }) {
    final ringColors = isAllRead
        ? [const Color(0xFF28A745), const Color(0xFF66BB6A)]
        : [AppColors.teacherPrimary, AppColors.teacherAccent];

    return Column(
      children: [
        Row(
          children: [
            // Engagement Ring
            Column(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: 0,
                      end: totalStudents > 0
                          ? (readCount / totalStudents).clamp(0.0, 1.0)
                          : 0.0,
                    ),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, child) {
                      return CustomPaint(
                        painter: EngagementRingPainter(
                          progress: progress,
                          gradientColors: ringColors,
                        ),
                        child: child,
                      );
                    },
                    child: Center(
                      child: AnimatedCountText(
                        value: engagementPercent,
                        suffix: '%',
                        style: TeacherTypography.statValue.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.charcoal.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'read today',
                  style: TeacherTypography.caption.copyWith(
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            // Stats Column
            Expanded(
              child: Column(
                children: [
                  _StatRow(
                    icon: Icons.menu_book_rounded,
                    dotColor: readCount > 0
                        ? AppColors.success
                        : AppColors.textSecondary,
                    value: '$readCount / $totalStudents',
                    label: 'read',
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap:
                        notReadCount > 0 ? _togglePendingView : null,
                    child: notReadCount > 0
                        ? _StatRow(
                            icon: Icons.schedule_rounded,
                            dotColor: AppColors.warmOrange,
                            value: '$notReadCount',
                            label: 'pending',
                          )
                        : _StatRow(
                            icon: Icons.schedule_rounded,
                            dotColor: AppColors.textSecondary,
                            value: '0',
                            label: 'pending',
                            isMuted: true,
                          ),
                  ),
                  const SizedBox(height: 14),
                  _StatRow(
                    icon: Icons.local_fire_department_rounded,
                    dotColor: onStreakCount > 0
                        ? AppColors.warmOrange
                        : AppColors.textSecondary,
                    value: '$onStreakCount',
                    label: 'on streak',
                    isMuted: onStreakCount == 0,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (totalMinutes > 0) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.teacherSurfaceTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$totalMinutes min read today',
              style: TeacherTypography.caption.copyWith(
                color: AppColors.charcoal,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final Color dotColor;
  final String value;
  final String label;
  final IconData? icon;
  final bool isMuted;

  const _StatRow({
    required this.dotColor,
    required this.value,
    required this.label,
    this.icon,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = isMuted
        ? AppColors.textSecondary
        : AppColors.charcoal.withValues(alpha: 0.7);

    return Row(
      children: [
        if (icon != null)
          Icon(icon, size: 16, color: dotColor)
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 10),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TeacherTypography.caption,
        ),
      ],
    );
  }
}
