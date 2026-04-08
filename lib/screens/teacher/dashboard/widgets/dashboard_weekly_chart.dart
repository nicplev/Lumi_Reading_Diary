import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
import '../../../../core/widgets/lumi_mascot.dart';
import '../../../../data/models/class_model.dart';
import '../../../../data/models/reading_log_model.dart';
import '../../../../services/firebase_service.dart';

/// Dashboard Weekly Chart
///
/// Elegant bar chart with stadium-pill gradient bars, ghost benchmark line,
/// touch tooltips with haptics, and beautiful empty/celebration states.
class DashboardWeeklyChart extends StatefulWidget {
  final ClassModel classModel;
  final String schoolId;

  const DashboardWeeklyChart({
    super.key,
    required this.classModel,
    required this.schoolId,
  });

  @override
  State<DashboardWeeklyChart> createState() => _DashboardWeeklyChartState();
}

class _DashboardWeeklyChartState extends State<DashboardWeeklyChart> {
  late Stream<QuerySnapshot> _weeklyStream;
  late DateTime _startOfWeek;
  int? _lastWeekTotal;
  int? _lastWeekDayCount;
  bool _lastWeekLoaded = false;

  @override
  void initState() {
    super.initState();
    _initStream();
    _fetchLastWeekData();
  }

  @override
  void didUpdateWidget(DashboardWeeklyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
      _fetchLastWeekData();
    }
  }

  void _initStream() {
    final now = DateTime.now();
    _startOfWeek = DateTime(now.year, now.month, now.day - (now.weekday - 1));

    _weeklyStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfWeek))
        .snapshots();
  }

  Future<void> _fetchLastWeekData() async {
    try {
      final now = DateTime.now();
      final startOfThisWeek =
          DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final startOfLastWeek =
          startOfThisWeek.subtract(const Duration(days: 7));

      final snapshot = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfLastWeek))
          .where('date', isLessThan: Timestamp.fromDate(startOfThisWeek))
          .get();

      if (!mounted) return;

      final logs = snapshot.docs
          .map((doc) => ReadingLogModel.fromFirestore(doc))
          .toList();

      // Count unique students per day, then sum
      final Map<int, Set<String>> studentsByDay = {};
      for (final log in logs) {
        final dayIndex = log.date.weekday - 1;
        studentsByDay.putIfAbsent(dayIndex, () => {}).add(log.studentId);
      }
      final total =
          studentsByDay.values.fold<int>(0, (acc, s) => acc + s.length);
      final daysWithData = studentsByDay.keys.length;

      setState(() {
        _lastWeekTotal = total;
        _lastWeekDayCount = daysWithData;
        _lastWeekLoaded = true;
      });
    } catch (e) {
      debugPrint('Error fetching last week data: $e');
      setState(() => _lastWeekLoaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalStudents = widget.classModel.studentIds.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: [
          BoxShadow(
            color: AppColors.charcoal.withValues(alpha: 0.04),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Weekly Reading Activity', style: TeacherTypography.h3),
              Text(
                'This Week',
                style: TeacherTypography.caption.copyWith(
                  color: AppColors.teacherPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _weeklyStream,
            builder: (context, snapshot) {
              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              final Map<int, Set<String>> studentsByDay = {};
              for (int i = 0; i < 7; i++) {
                studentsByDay[i] = {};
              }
              for (final log in logs) {
                final date = log.date;
                final dayIndex = _startOfWeek
                        .difference(DateTime(date.year, date.month, date.day))
                        .inDays
                        .abs();
                if (dayIndex >= 0 && dayIndex < 7) {
                  studentsByDay[dayIndex]!.add(log.studentId);
                }
              }

              final Map<int, int> completionByDay = {};
              for (int i = 0; i < 7; i++) {
                completionByDay[i] = studentsByDay[i]!.length;
              }

              final todayIndex = DateTime.now().weekday - 1;
              final totalWeek =
                  completionByDay.values.fold<int>(0, (a, b) => a + b);

              if (totalWeek == 0) {
                return _buildEmptyState(totalStudents);
              }

              // Check celebration state
              bool isAllReadEveryDay = totalStudents > 0;
              for (int i = 0; i <= todayIndex && isAllReadEveryDay; i++) {
                if ((completionByDay[i] ?? 0) < totalStudents) {
                  isAllReadEveryDay = false;
                }
              }

              final daysElapsed = todayIndex + 1;
              final avgPerDay =
                  daysElapsed > 0 ? (totalWeek / daysElapsed).round() : 0;
              final avgPercent = totalStudents > 0
                  ? (avgPerDay / totalStudents * 100).round()
                  : 0;

              return Column(
                children: [
                  if (isAllReadEveryDay) ...[
                    _buildCelebrationBadge(),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    height: 170,
                    child: BarChart(
                      BarChartData(
                        barGroups:
                            _buildBarGroups(completionByDay, todayIndex, totalStudents),
                        maxY: max(totalStudents.toDouble(), 1),
                        alignment: BarChartAlignment.spaceAround,
                        titlesData: _buildTitlesData(completionByDay, todayIndex),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval:
                              max((totalStudents / 3).ceilToDouble(), 1),
                          getDrawingHorizontalLine: (_) => FlLine(
                            color: AppColors.teacherBorder
                                .withValues(alpha: 0.5),
                            strokeWidth: 0.5,
                            dashArray: [4, 4],
                          ),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            // Ghost benchmark line at total students
                            HorizontalLine(
                              y: totalStudents.toDouble(),
                              color: AppColors.teacherBorder
                                  .withValues(alpha: 0.6),
                              strokeWidth: 1,
                              dashArray: [6, 4],
                            ),
                          ],
                        ),
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchCallback: (event, response) {
                            if (event is FlTapUpEvent &&
                                response?.spot != null) {
                              HapticFeedback.lightImpact();
                            }
                          },
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) =>
                                AppColors.charcoal.withValues(alpha: 0.9),
                            tooltipBorderRadius: BorderRadius.circular(12),
                            tooltipPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            getTooltipItem:
                                (group, groupIndex, rod, rodIndex) {
                              const days = [
                                'Monday',
                                'Tuesday',
                                'Wednesday',
                                'Thursday',
                                'Friday',
                                'Saturday',
                                'Sunday'
                              ];
                              final count = rod.toY.toInt();
                              final pct = totalStudents > 0
                                  ? (count / totalStudents * 100).round()
                                  : 0;
                              return BarTooltipItem(
                                '${days[groupIndex]}\n',
                                TeacherTypography.caption.copyWith(
                                  color: AppColors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        '$count/$totalStudents read · $pct%',
                                    style: TeacherTypography.caption.copyWith(
                                      color: AppColors.white
                                          .withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFooter(avgPerDay, totalStudents, avgPercent),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups(
    Map<int, int> completionByDay,
    int todayIndex,
    int totalStudents,
  ) {
    return List.generate(7, (index) {
      final count = completionByDay[index]?.toDouble() ?? 0;
      final isToday = index == todayIndex;
      final isFuture = index > todayIndex;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: isFuture ? 0.3 : count,
            width: 24,
            borderRadius: BorderRadius.circular(6),
            gradient: isFuture
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isToday
                        ? [
                            AppColors.teacherPrimary
                                .withValues(alpha: 0.7),
                            AppColors.teacherPrimary
                                .withValues(alpha: 0.07),
                          ]
                        : [
                            AppColors.teacherPrimary,
                            AppColors.teacherPrimary
                                .withValues(alpha: 0.10),
                          ],
                  ),
            color: isFuture ? const Color(0xFFF0F4F8) : null,
          ),
        ],
        showingTooltipIndicators: [],
      );
    });
  }

  FlTitlesData _buildTitlesData(
      Map<int, int> completionByDay, int todayIndex) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
            final index = value.toInt();
            final isToday = index == todayIndex;
            final isFuture = index > todayIndex;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                days[index],
                style: TeacherTypography.caption.copyWith(
                  color: isToday
                      ? AppColors.teacherPrimary
                      : isFuture
                          ? AppColors.textSecondary
                              .withValues(alpha: 0.4)
                          : AppColors.textSecondary,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ),
      topTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 20,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            final count = completionByDay[index] ?? 0;
            final todayIndex = DateTime.now().weekday - 1;
            if (count == 0 || index > todayIndex) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$count',
                style: TeacherTypography.caption.copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
      ),
      leftTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
    );
  }

  Widget _buildFooter(int avgPerDay, int totalStudents, int avgPercent) {
    // Compute week-over-week trend
    String? trendText;
    Color? trendColor;
    IconData? trendIcon;

    if (_lastWeekLoaded && _lastWeekTotal != null && _lastWeekDayCount != null) {
      final lastAvg = _lastWeekDayCount! > 0
          ? (_lastWeekTotal! / _lastWeekDayCount!).round()
          : 0;
      final lastPercent = totalStudents > 0
          ? (lastAvg / totalStudents * 100).round()
          : 0;
      final diff = avgPercent - lastPercent;
      if (diff > 0) {
        trendText = '+$diff% vs last week';
        trendColor = AppColors.success;
        trendIcon = Icons.trending_up_rounded;
      } else if (diff < 0) {
        trendText = '$diff% vs last week';
        trendColor = AppColors.warmOrange;
        trendIcon = Icons.trending_down_rounded;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.teacherBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Avg $avgPerDay/$totalStudents per night',
            style: TeacherTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (trendText != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, size: 14, color: trendColor),
                const SizedBox(width: 3),
                Text(
                  trendText,
                  style: TeacherTypography.caption.copyWith(
                    color: trendColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(int totalStudents) {
    const ghostHeights = [0.45, 0.7, 0.55, 0.8, 0.4, 0.3, 0.25];
    const maxBarHeight = 80.0;

    return Column(
      children: [
        const SizedBox(height: 8),
        const LumiMascot(mood: LumiMood.encouraging, size: 48),
        const SizedBox(height: 8),
        Text(
          "Your class's reading week starts here",
          style: TeacherTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.charcoal,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        // Ghost bars
        SizedBox(
          height: maxBarHeight + 28,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (index) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 24,
                    height: maxBarHeight * ghostHeights[index],
                    decoration: BoxDecoration(
                      color:
                          AppColors.teacherPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                    style: TeacherTypography.caption.copyWith(
                      color:
                          AppColors.textSecondary.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildCelebrationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F7EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Everyone's read this week",
            style: TeacherTypography.caption.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
