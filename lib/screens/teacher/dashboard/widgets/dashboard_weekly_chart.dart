import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/widgets/inline_stream_error.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
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
  static const String _offsetPrefsKey = 'dashboard_week_offset';

  late Stream<QuerySnapshot> _weeklyStream;
  late DateTime _startOfWeek;

  /// Monday-anchored week being shown: 0 = this week, -1 = last week. The
  /// Monday-morning ritual is "who read last week?" — exactly when the
  /// current week's chart is empty, so the timeframe is selectable.
  int _weekOffset = 0;
  int? _prevWeekTotal;
  int? _prevWeekDayCount;
  bool _prevWeekLoaded = false;

  @override
  void initState() {
    super.initState();
    _initStream();
    _fetchComparisonWeekData();
    _restoreSavedOffset();
  }

  @override
  void didUpdateWidget(DashboardWeeklyChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id ||
        oldWidget.schoolId != widget.schoolId) {
      _initStream();
      _fetchComparisonWeekData();
    }
  }

  Future<void> _restoreSavedOffset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_offsetPrefsKey) ?? 0;
      if (mounted && saved != _weekOffset && (saved == 0 || saved == -1)) {
        _setWeekOffset(saved, persist: false);
      }
    } catch (_) {
      // Preference restore is a nicety — default to this week.
    }
  }

  void _setWeekOffset(int offset, {bool persist = true}) {
    setState(() {
      _weekOffset = offset;
      _initStream();
    });
    _fetchComparisonWeekData();
    if (persist) {
      SharedPreferences.getInstance()
          .then((p) => p.setInt(_offsetPrefsKey, offset))
          .catchError((_) => true);
    }
  }

  void _initStream() {
    final now = DateTime.now();
    _startOfWeek = DateTime(
        now.year, now.month, now.day - (now.weekday - 1) + 7 * _weekOffset);
    final endOfWeek = _startOfWeek.add(const Duration(days: 7));

    _weeklyStream = FirebaseService.instance.firestore
        .collection('schools')
        .doc(widget.schoolId)
        .collection('readingLogs')
        .where('classId', isEqualTo: widget.classModel.id)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfWeek))
        .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
        .snapshots();
  }

  /// Fetch the week *before* the displayed one, for the trend footer.
  Future<void> _fetchComparisonWeekData() async {
    final requestOffset = _weekOffset;
    try {
      final now = DateTime.now();
      final startOfShownWeek = DateTime(
          now.year, now.month, now.day - (now.weekday - 1) + 7 * requestOffset);
      final startOfPrevWeek =
          startOfShownWeek.subtract(const Duration(days: 7));

      final snapshot = await FirebaseService.instance.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('classId', isEqualTo: widget.classModel.id)
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfPrevWeek))
          .where('date', isLessThan: Timestamp.fromDate(startOfShownWeek))
          .get();

      // A stale response for a different offset must not clobber the footer.
      if (!mounted || requestOffset != _weekOffset) return;

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
        _prevWeekTotal = total;
        _prevWeekDayCount = daysWithData;
        _prevWeekLoaded = true;
      });
    } catch (e) {
      debugPrint('Error fetching comparison week data: $e');
      if (mounted && requestOffset == _weekOffset) {
        setState(() => _prevWeekLoaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalStudents = widget.classModel.studentIds.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text('Weekly Reading Activity', style: LumiType.subhead),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _weekChip('This week', 0),
                  const SizedBox(width: 6),
                  _weekChip('Last week', -1),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Students who logged reading each day',
            style: LumiType.caption.copyWith(color: LumiTokens.muted),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: _weeklyStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const InlineStreamError(message: "Couldn't load this week's reading.");
              }
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

              // Past weeks are complete — every day counts, none is "today".
              final todayIndex =
                  _weekOffset == 0 ? DateTime.now().weekday - 1 : 6;
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
                            color: LumiTokens.rule,
                            strokeWidth: 0.5,
                            dashArray: [4, 4],
                          ),
                        ),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            // Ghost benchmark line at total students
                            HorizontalLine(
                              y: totalStudents.toDouble(),
                              color: LumiTokens.rule,
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
                                LumiTokens.ink.withValues(alpha: 0.9),
                            tooltipBorderRadius:
                                BorderRadius.circular(LumiTokens.radiusMedium),
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
                                LumiType.caption.copyWith(
                                  color: LumiTokens.paper,
                                  fontWeight: FontWeight.w700,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        '$count/$totalStudents read · $pct%',
                                    style: LumiType.caption.copyWith(
                                      color: LumiTokens.paper
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
                  _buildFooter(avgPerDay, totalStudents),
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
      final isToday = _weekOffset == 0 && index == todayIndex;
      final isFuture = index > todayIndex;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: isFuture ? 0.3 : count,
            width: 24,
            borderRadius: BorderRadius.circular(6),
            color: isFuture
                ? LumiTokens.rule
                : isToday
                    ? LumiTokens.blue
                    : LumiTokens.blue.withValues(alpha: 0.55),
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
            final isToday = _weekOffset == 0 && index == todayIndex;
            final isFuture = index > todayIndex;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                days[index],
                style: LumiType.caption.copyWith(
                  color: isToday
                      ? LumiTokens.blue
                      : isFuture
                          ? LumiTokens.muted.withValues(alpha: 0.4)
                          : LumiTokens.muted,
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
            if (count == 0 || index > todayIndex) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$count',
                style: LumiType.caption.copyWith(fontSize: 11),
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

  /// Compact pill for the This week / Last week timeframe toggle.
  Widget _weekChip(String label, int offset) {
    final selected = _weekOffset == offset;
    return GestureDetector(
      onTap: selected ? null : () => _setWeekOffset(offset),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? LumiTokens.blue : LumiTokens.cream,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: LumiType.caption.copyWith(
            color: selected ? LumiTokens.paper : LumiTokens.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(int avgPerDay, int totalStudents) {
    // Week-over-week trend in students, not a percentage — a % on small class
    // sizes overstates tiny changes (0.75 → 1 student reads as "+33%").
    String? trendText;
    Color? trendColor;
    IconData? trendIcon;

    // Compared against the week before the one on screen.
    final vsLabel =
        _weekOffset == 0 ? 'than last week' : 'than the week before';
    if (_prevWeekLoaded && _prevWeekTotal != null && _prevWeekDayCount != null) {
      final lastAvg = _prevWeekDayCount! > 0
          ? (_prevWeekTotal! / _prevWeekDayCount!).round()
          : 0;
      final diff = avgPerDay - lastAvg;
      if (diff > 0) {
        trendText = diff == 1 ? '1 more $vsLabel' : '$diff more $vsLabel';
        trendColor = LumiTokens.green;
        trendIcon = Icons.trending_up_rounded;
      } else if (diff < 0) {
        final n = diff.abs();
        trendText = n == 1 ? '1 fewer $vsLabel' : '$n fewer $vsLabel';
        trendColor = LumiTokens.red;
        trendIcon = Icons.trending_down_rounded;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Avg $avgPerDay of $totalStudents per night',
            style: LumiType.caption.copyWith(color: LumiTokens.muted),
          ),
          if (trendText != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(trendIcon, size: 14, color: trendColor),
                const SizedBox(width: 3),
                Text(
                  trendText,
                  style: LumiType.caption.copyWith(
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
        const LumiMascot(variant: LumiVariant.teacherWhy, size: 48),
        const SizedBox(height: 8),
        Text(
          _weekOffset == 0
              ? "Your class's reading week starts here"
              : 'No reading was logged that week',
          style: LumiType.body.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 15,
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
                      color: LumiTokens.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.muted.withValues(alpha: 0.4),
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
        color: LumiTokens.tintGreen,
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        border: Border.all(
          color: LumiTokens.green.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _weekOffset == 0
                ? "Everyone's read this week"
                : 'Everyone read that week',
            style: LumiType.caption.copyWith(
              color: LumiTokens.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
