import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';

class ReadingHistoryScreen extends StatefulWidget {
  final String studentId;
  final String parentId;
  final String schoolId;

  const ReadingHistoryScreen({
    super.key,
    required this.studentId,
    required this.parentId,
    required this.schoolId,
  });

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseService _firebaseService = FirebaseService.instance;
  DateTime _selectedMonth = DateTime.now();
  String _selectedView = 'list'; // 'list' or 'chart'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Reading History', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(child: Text('This Week', style: LumiTextStyles.label())),
            Tab(child: Text('This Month', style: LumiTextStyles.label())),
            Tab(child: Text('All Time', style: LumiTextStyles.label())),
          ],
          labelColor: AppColors.rosePink,
          unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.7),
          indicatorColor: AppColors.rosePink,
        ),
        actions: [
          LumiIconButton(
            icon: _selectedView == 'list' ? Icons.bar_chart : Icons.list,
            onPressed: () {
              setState(() {
                _selectedView = _selectedView == 'list' ? 'chart' : 'list';
              });
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildWeekView(),
          _buildMonthView(),
          _buildAllTimeView(),
        ],
      ),
    );
  }

  Widget _buildWeekView() {
    final startOfWeek = DateTime.now().subtract(
      Duration(days: DateTime.now().weekday - 1),
    );
    final endOfWeek = startOfWeek.add(const Duration(days: 7));

    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.studentId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek))
          .where('date', isLessThan: Timestamp.fromDate(endOfWeek))
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        if (_selectedView == 'chart') {
          return _buildWeekChart(logs, startOfWeek);
        }

        return _buildLogsList(logs, 'No reading logs this week');
      },
    );
  }

  Widget _buildMonthView() {
    final startOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final endOfMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    return Column(
      children: [
        // Month selector
        Container(
          color: AppColors.white,
          padding: EdgeInsets.symmetric(horizontal: LumiSpacing.s, vertical: LumiSpacing.xs),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              LumiIconButton(
                icon: Icons.chevron_left,
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    );
                  });
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(_selectedMonth),
                style: LumiTextStyles.h3(),
              ),
              LumiIconButton(
                icon: Icons.chevron_right,
                onPressed: _selectedMonth.month == DateTime.now().month &&
                        _selectedMonth.year == DateTime.now().year
                    ? null
                    : () {
                        setState(() {
                          _selectedMonth = DateTime(
                            _selectedMonth.year,
                            _selectedMonth.month + 1,
                          );
                        });
                      },
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firebaseService.firestore
                .collection('schools')
                .doc(widget.schoolId)
                .collection('readingLogs')
                .where('studentId', isEqualTo: widget.studentId)
                .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
                .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final logs = snapshot.data?.docs
                      .map((doc) => ReadingLogModel.fromFirestore(doc))
                      .toList() ??
                  [];

              if (_selectedView == 'chart') {
                return _buildMonthChart(logs, startOfMonth, endOfMonth);
              }

              return _buildLogsList(logs, 'No reading logs this month');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAllTimeView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firebaseService.firestore
          .collection('schools')
          .doc(widget.schoolId)
          .collection('readingLogs')
          .where('studentId', isEqualTo: widget.studentId)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data?.docs
                .map((doc) => ReadingLogModel.fromFirestore(doc))
                .toList() ??
            [];

        if (logs.isEmpty) {
          return _buildEmptyState('No reading logs yet');
        }

        // Calculate statistics
        final totalMinutes = logs.fold<int>(0, (sum, log) => sum + log.minutesRead);
        final totalBooks = logs.fold<int>(0, (sum, log) => sum + log.bookTitles.length);
        final averageMinutes = totalMinutes ~/ logs.length;

        return Column(
          children: [
            // Statistics cards
            Padding(
              padding: LumiPadding.allS,
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Total Time',
                      value: '${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
                      icon: Icons.timer,
                      color: AppColors.rosePink,
                    ),
                  ),
                  LumiGap.horizontalS,
                  Expanded(
                    child: _StatCard(
                      title: 'Books Read',
                      value: totalBooks.toString(),
                      icon: Icons.book,
                      color: AppColors.secondaryPurple,
                    ),
                  ),
                  LumiGap.horizontalS,
                  Expanded(
                    child: _StatCard(
                      title: 'Avg/Day',
                      value: '${averageMinutes}m',
                      icon: Icons.trending_up,
                      color: AppColors.mintGreen,
                    ),
                  ),
                ],
              ),
            ),

            if (_selectedView == 'chart') ...[
              Expanded(
                child: _buildYearChart(logs),
              ),
            ] else ...[
              Expanded(
                child: _buildLogsList(logs, 'No reading logs'),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLogsList(List<ReadingLogModel> logs, String emptyMessage) {
    if (logs.isEmpty) {
      return _buildEmptyState(emptyMessage);
    }

    return ListView.builder(
      padding: LumiPadding.allS,
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return _LogCard(log: log);
      },
    );
  }

  Widget _buildWeekChart(List<ReadingLogModel> logs, DateTime startOfWeek) {
    final Map<int, int> minutesByDay = {};
    for (int i = 0; i < 7; i++) {
      minutesByDay[i] = 0;
    }

    for (final log in logs) {
      final dayIndex = log.date.difference(startOfWeek).inDays;
      if (dayIndex >= 0 && dayIndex < 7) {
        minutesByDay[dayIndex] = (minutesByDay[dayIndex] ?? 0) + log.minutesRead;
      }
    }

    return Padding(
      padding: LumiPadding.allS,
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                barGroups: List.generate(7, (index) {
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (minutesByDay[index] ?? 0).toDouble(),
                        color: AppColors.rosePink,
                        width: 30,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ],
                  );
                }),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final date = startOfWeek.add(Duration(days: value.toInt()));
                        return Text(
                          DateFormat('E').format(date).substring(0, 1),
                          style: LumiTextStyles.bodySmall(),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}m',
                          style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: true),
              ),
            ),
          ),
          LumiGap.s,
          Text(
            'Total: ${minutesByDay.values.fold(0, (a, b) => a + b)} minutes',
            style: LumiTextStyles.h3(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthChart(
      List<ReadingLogModel> logs, DateTime startOfMonth, DateTime endOfMonth) {
    final daysInMonth = endOfMonth.day;
    final Map<int, int> minutesByDay = {};

    for (final log in logs) {
      minutesByDay[log.date.day] = (minutesByDay[log.date.day] ?? 0) + log.minutesRead;
    }

    final List<FlSpot> spots = [];
    for (int day = 1; day <= daysInMonth; day++) {
      spots.add(FlSpot(day.toDouble(), (minutesByDay[day] ?? 0).toDouble()));
    }

    return Padding(
      padding: LumiPadding.allS,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.rosePink,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: spot.y > 0 ? 4 : 0,
                    color: AppColors.rosePink,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.rosePink.withValues(alpha: 0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${value.toInt()}m',
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true),
        ),
      ),
    );
  }

  Widget _buildYearChart(List<ReadingLogModel> logs) {
    // Group logs by month
    final Map<String, int> minutesByMonth = {};

    for (final log in logs) {
      final monthKey = DateFormat('MMM').format(log.date);
      minutesByMonth[monthKey] = (minutesByMonth[monthKey] ?? 0) + log.minutesRead;
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    final currentMonth = DateTime.now().month;

    return Padding(
      padding: LumiPadding.allS,
      child: BarChart(
        BarChartData(
          barGroups: List.generate(currentMonth, (index) {
            final month = months[index];
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (minutesByMonth[month] ?? 0).toDouble(),
                  color: AppColors.rosePink,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < currentMonth) {
                    return Text(
                      months[value.toInt()],
                      style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${(value / 60).toStringAsFixed(0)}h',
                    style: LumiTextStyles.bodySmall().copyWith(fontSize: 10),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: true),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.book_outlined,
            size: 64,
            color: AppColors.charcoal.withValues(alpha: 0.5),
          ),
          LumiGap.s,
          Text(
            message,
            style: LumiTextStyles.h3().copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final ReadingLogModel log;

  const _LogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: LumiSpacing.xs),
      child: LumiCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.rosePink.withValues(alpha: 0.1),
              borderRadius: LumiBorders.medium,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd').format(log.date),
                  style: LumiTextStyles.h3().copyWith(
                    color: AppColors.rosePink,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(log.date),
                  style: LumiTextStyles.bodySmall().copyWith(
                    color: AppColors.rosePink,
                  ),
                ),
              ],
            ),
          ),
          title: Text(
            log.bookTitles.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LumiTextStyles.h3(),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LumiGap.xxs,
              Row(
                children: [
                  Icon(
                    Icons.timer,
                    size: 16,
                    color: log.hasMetTarget
                        ? AppColors.mintGreen
                        : AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                  LumiGap.horizontalXXS,
                  Text(
                    '${log.minutesRead} minutes',
                    style: LumiTextStyles.bodySmall().copyWith(
                      color: log.hasMetTarget
                          ? AppColors.mintGreen
                          : AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  if (log.hasMetTarget) ...[
                    LumiGap.horizontalXS,
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: LumiSpacing.xxs, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.mintGreen.withValues(alpha: 0.1),
                        borderRadius: LumiBorders.circular,
                      ),
                      child: Text(
                        'Goal Met',
                        style: LumiTextStyles.label().copyWith(
                          color: AppColors.mintGreen,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (log.notes != null && log.notes!.isNotEmpty) ...[
                LumiGap.xxs,
                Text(
                  log.notes!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LumiTextStyles.bodySmall().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ],
              if (log.teacherComment != null) ...[
                LumiGap.xxs,
                Container(
                  padding: LumiPadding.allXS,
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: LumiBorders.small,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.comment,
                        size: 16,
                        color: AppColors.info,
                      ),
                      LumiGap.horizontalXXS,
                      Expanded(
                        child: Text(
                          'Teacher: ${log.teacherComment}',
                          style: LumiTextStyles.bodySmall().copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          trailing: log.isCompleted
              ? const Icon(
                  Icons.check_circle,
                  color: AppColors.mintGreen,
                )
              : Icon(
                  Icons.circle_outlined,
                  color: AppColors.charcoal.withValues(alpha: 0.7),
                ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LumiCard(
      padding: LumiPadding.allS,
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          LumiGap.xs,
          Text(
            value,
            style: LumiTextStyles.h2().copyWith(
              color: AppColors.charcoal,
            ),
          ),
          Text(
            title,
            style: LumiTextStyles.bodySmall().copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}