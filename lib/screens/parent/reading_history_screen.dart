import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_colors.dart';
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
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Reading History'),
        backgroundColor: AppColors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'This Week'),
            Tab(text: 'This Month'),
            Tab(text: 'All Time'),
          ],
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.primaryBlue,
        ),
        actions: [
          IconButton(
            icon: Icon(
              _selectedView == 'list' ? Icons.bar_chart : Icons.list,
              color: AppColors.darkGray,
            ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
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
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Total Time',
                      value: '${totalMinutes ~/ 60}h ${totalMinutes % 60}m',
                      icon: Icons.timer,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Books Read',
                      value: totalBooks.toString(),
                      icon: Icons.book,
                      color: AppColors.secondaryPurple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Avg/Day',
                      value: '${averageMinutes}m',
                      icon: Icons.trending_up,
                      color: AppColors.secondaryGreen,
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
      padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
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
                        color: AppColors.primaryBlue,
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
                          style: const TextStyle(fontSize: 12),
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
                          style: const TextStyle(fontSize: 10),
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
          const SizedBox(height: 16),
          Text(
            'Total: ${minutesByDay.values.fold(0, (a, b) => a + b)} minutes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.primaryBlue,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: spot.y > 0 ? 4 : 0,
                    color: AppColors.primaryBlue,
                    strokeWidth: 0,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primaryBlue.withOpacity(0.1),
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
                    style: const TextStyle(fontSize: 10),
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
                    style: const TextStyle(fontSize: 10),
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
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          barGroups: List.generate(currentMonth, (index) {
            final month = months[index];
            return BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (minutesByMonth[month] ?? 0).toDouble(),
                  color: AppColors.primaryBlue,
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
                      style: const TextStyle(fontSize: 10),
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
                    style: const TextStyle(fontSize: 10),
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
            color: AppColors.gray.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.gray,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('dd').format(log.date),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
              ),
              Text(
                DateFormat('MMM').format(log.date),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.primaryBlue,
                    ),
              ),
            ],
          ),
        ),
        title: Text(
          log.bookTitles.join(', '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.timer,
                  size: 16,
                  color: log.hasMetTarget
                      ? AppColors.secondaryGreen
                      : AppColors.gray,
                ),
                const SizedBox(width: 4),
                Text(
                  '${log.minutesRead} minutes',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: log.hasMetTarget
                            ? AppColors.secondaryGreen
                            : AppColors.gray,
                      ),
                ),
                if (log.hasMetTarget) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Goal Met',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.secondaryGreen,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                ],
              ],
            ),
            if (log.notes != null && log.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                log.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray,
                    ),
              ),
            ],
            if (log.teacherComment != null) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.comment,
                      size: 16,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Teacher: ${log.teacherComment}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                color: AppColors.secondaryGreen,
              )
            : const Icon(
                Icons.circle_outlined,
                color: AppColors.gray,
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGray,
                  ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}