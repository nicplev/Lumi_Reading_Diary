import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/class_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

/// Comprehensive analytics dashboard for school administrators
/// Provides executive-level insights into reading program performance
class SchoolAnalyticsDashboard extends StatefulWidget {
  final String schoolId;

  const SchoolAnalyticsDashboard({
    super.key,
    required this.schoolId,
  });

  @override
  State<SchoolAnalyticsDashboard> createState() =>
      _SchoolAnalyticsDashboardState();
}

class _SchoolAnalyticsDashboardState extends State<SchoolAnalyticsDashboard> {
  bool _isLoading = true;
  String? _error;

  // Data
  List<ClassModel> _classes = [];
  final Map<String, List<StudentModel>> _studentsByClass = {};
  final Map<String, Map<String, dynamic>> _classMetrics = {};
  Map<String, dynamic>? _schoolMetrics;

  // Date range for analytics
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadAnalyticsData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Analytics Dashboard'),
        backgroundColor: AppColors.rosePink,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _showDateRangePicker,
            tooltip: 'Change Date Range',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadAnalyticsData,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildDateRangeBanner(),
                        const SizedBox(height: 16),
                        _buildExecutiveSummary(),
                        const SizedBox(height: 24),
                        _buildEngagementMetrics(),
                        const SizedBox(height: 24),
                        _buildReadingTrendsChart(),
                        const SizedBox(height: 24),
                        _buildClassComparison(),
                        const SizedBox(height: 24),
                        _buildAtRiskStudents(),
                        const SizedBox(height: 24),
                        _buildTopPerformingClasses(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline,
              size: 64, color: AppColors.error.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          Text(
            'Error loading analytics',
            style: LumiTextStyles.h2(),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? 'Unknown error',
            style: LumiTextStyles.body().copyWith(
              color: AppColors.charcoal.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          LumiPrimaryButton(
            onPressed: _loadAnalyticsData,
            text: 'Retry',
            icon: Icons.refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeBanner() {
    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.date_range, color: AppColors.rosePink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics Period',
                    style: LumiTextStyles.label().copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
                  ),
                  Text(
                    '${DateFormat('MMM dd, yyyy').format(_startDate)} - ${DateFormat('MMM dd, yyyy').format(_endDate)}',
                    style: LumiTextStyles.h3().copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            LumiTextButton(
              onPressed: _showDateRangePicker,
              text: 'Change',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveSummary() {
    if (_schoolMetrics == null) return const SizedBox.shrink();

    final metrics = _schoolMetrics!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Executive Summary',
          style: LumiTextStyles.h2().copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _buildMetricCard(
              'Total Students',
              '${metrics['totalStudents']}',
              Icons.people,
              AppColors.rosePink,
              subtitle: '${metrics['activeStudents']} active',
            ),
            _buildMetricCard(
              'Total Classes',
              '${metrics['totalClasses']}',
              Icons.class_,
              AppColors.rosePink,
            ),
            _buildMetricCard(
              'Reading Minutes',
              _formatNumber(metrics['totalMinutes']),
              Icons.schedule,
              AppColors.mintGreen,
              subtitle: 'Last ${_endDate.difference(_startDate).inDays} days',
            ),
            _buildMetricCard(
              'Engagement Rate',
              '${metrics['engagementRate'].toStringAsFixed(0)}%',
              Icons.trending_up,
              AppColors.warmOrange,
              subtitle: 'Students reading regularly',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: LumiTextStyles.h1().copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: LumiTextStyles.label().copyWith(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: LumiTextStyles.label().copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngagementMetrics() {
    if (_schoolMetrics == null) return const SizedBox.shrink();

    final metrics = _schoolMetrics!;

    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Engagement & Performance',
              style: LumiTextStyles.h3().copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildProgressRow(
              'Students Meeting Daily Target',
              metrics['studentsMetTarget'] ?? 0,
              metrics['totalStudents'] ?? 1,
              AppColors.mintGreen,
            ),
            const SizedBox(height: 12),
            _buildProgressRow(
              'Students with Active Streak',
              metrics['studentsWithStreak'] ?? 0,
              metrics['totalStudents'] ?? 1,
              AppColors.warmOrange,
            ),
            const SizedBox(height: 12),
            _buildProgressRow(
              'Classes Above Average',
              metrics['classesAboveAverage'] ?? 0,
              metrics['totalClasses'] ?? 1,
              AppColors.rosePink,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn(
                    'Avg Minutes/Student',
                    '${metrics['avgMinutesPerStudent']?.toStringAsFixed(1) ?? "0"}',
                    AppColors.skyBlue,
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'Total Books Read',
                    '${metrics['totalBooks'] ?? 0}',
                    AppColors.skyBlue,
                  ),
                ),
                Expanded(
                  child: _buildStatColumn(
                    'Longest Streak',
                    '${metrics['longestStreak'] ?? 0} days',
                    AppColors.softYellow,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressRow(String label, int current, int total, Color color) {
    final percentage = total > 0 ? (current / total) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: LumiTextStyles.body(),
            ),
            Text(
              '$current / $total (${(percentage * 100).toStringAsFixed(0)}%)',
              style: LumiTextStyles.body().copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: percentage,
          backgroundColor: color.withValues(alpha: 0.2),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: LumiTextStyles.h2().copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: LumiTextStyles.label().copyWith(
            color: AppColors.charcoal.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildReadingTrendsChart() {
    if (_schoolMetrics == null) return const SizedBox.shrink();

    final weeklyData =
        _schoolMetrics!['weeklyData'] as List<Map<String, dynamic>>? ?? [];

    if (weeklyData.isEmpty) {
      return const SizedBox.shrink();
    }

    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reading Trends (Weekly)',
              style: LumiTextStyles.h3().copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 1000,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: AppColors.charcoal.withValues(alpha: 0.1),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 &&
                              value.toInt() < weeklyData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                weeklyData[value.toInt()]['label'] as String,
                                style: LumiTextStyles.label(),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1000,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${(value / 1000).toStringAsFixed(0)}k',
                            style: LumiTextStyles.label(),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(
                        color: AppColors.charcoal.withValues(alpha: 0.1)),
                  ),
                  minX: 0,
                  maxX: (weeklyData.length - 1).toDouble(),
                  minY: 0,
                  maxY: _getMaxYValue(weeklyData),
                  lineBarsData: [
                    LineChartBarData(
                      spots: weeklyData.asMap().entries.map((entry) {
                        return FlSpot(
                          entry.key.toDouble(),
                          (entry.value['minutes'] as int).toDouble(),
                        );
                      }).toList(),
                      isCurved: true,
                      color: AppColors.rosePink,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.rosePink.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxYValue(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return 1000;

    final maxMinutes = data
        .map((e) => e['minutes'] as int)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    // Round up to nearest thousand and add some padding
    return ((maxMinutes / 1000).ceil() * 1000 * 1.2);
  }

  Widget _buildClassComparison() {
    if (_classes.isEmpty) return const SizedBox.shrink();

    // Sort classes by total minutes read (descending)
    final sortedClasses = List<ClassModel>.from(_classes);
    sortedClasses.sort((a, b) {
      final aMinutes = _classMetrics[a.id]?['totalMinutes'] ?? 0;
      final bMinutes = _classMetrics[b.id]?['totalMinutes'] ?? 0;
      return bMinutes.compareTo(aMinutes);
    });

    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Class Performance Comparison',
              style: LumiTextStyles.h3().copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1),
              },
              border: TableBorder.all(
                  color: AppColors.charcoal.withValues(alpha: 0.1)),
              children: [
                // Header
                TableRow(
                  decoration: BoxDecoration(
                      color: AppColors.charcoal.withValues(alpha: 0.03)),
                  children: [
                    _buildTableHeader('Class'),
                    _buildTableHeader('Students'),
                    _buildTableHeader('Minutes'),
                    _buildTableHeader('Avg/Student'),
                  ],
                ),
                // Data rows
                ...sortedClasses.map((classModel) {
                  final metrics = _classMetrics[classModel.id];
                  final totalMinutes = metrics?['totalMinutes'] ?? 0;
                  final studentCount =
                      _studentsByClass[classModel.id]?.length ?? 0;
                  final avgPerStudent = studentCount > 0
                      ? (totalMinutes / studentCount).round()
                      : 0;

                  return TableRow(
                    children: [
                      _buildTableCell(classModel.name),
                      _buildTableCell('$studentCount'),
                      _buildTableCell('$totalMinutes'),
                      _buildTableCell('$avgPerStudent'),
                    ],
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: LumiTextStyles.body().copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: LumiTextStyles.label(),
      ),
    );
  }

  Widget _buildAtRiskStudents() {
    if (_schoolMetrics == null) return const SizedBox.shrink();

    final atRiskStudents =
        _schoolMetrics!['atRiskStudents'] as List<Map<String, dynamic>>? ?? [];

    if (atRiskStudents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.mintGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.mintGreen, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'No students currently at risk! All students are actively engaged.',
                  style: LumiTextStyles.h3().copyWith(
                    color: AppColors.success,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warmOrange),
                const SizedBox(width: 8),
                Text(
                  'Students Needing Support (${atRiskStudents.length})',
                  style: LumiTextStyles.h3().copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...atRiskStudents.take(10).map((student) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          AppColors.warmOrange.withValues(alpha: 0.2),
                      child: Text(
                        (student['name'] as String)[0].toUpperCase(),
                        style: LumiTextStyles.h3(color: AppColors.warmOrange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student['name'] as String,
                            style: LumiTextStyles.body()
                                .copyWith(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            student['className'] as String,
                            style: LumiTextStyles.label(
                              color: AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warmOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warmOrange.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        student['issue'] as String,
                        style: LumiTextStyles.label(
                          color: AppColors.warmOrange,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            if (atRiskStudents.length > 10) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () {
                    // Show all at-risk students
                    _showAllAtRiskStudents(atRiskStudents);
                  },
                  child: Text('View all ${atRiskStudents.length} students'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopPerformingClasses() {
    if (_classes.isEmpty) return const SizedBox.shrink();

    // Get top 3 classes by average minutes per student
    final sortedClasses = List<ClassModel>.from(_classes);
    sortedClasses.sort((a, b) {
      final aStudents = _studentsByClass[a.id]?.length ?? 0;
      final bStudents = _studentsByClass[b.id]?.length ?? 0;

      if (aStudents == 0) return 1;
      if (bStudents == 0) return -1;

      final aAvg = (_classMetrics[a.id]?['totalMinutes'] ?? 0) / aStudents;
      final bAvg = (_classMetrics[b.id]?['totalMinutes'] ?? 0) / bStudents;

      return bAvg.compareTo(aAvg);
    });

    final topClasses = sortedClasses.take(3).toList();

    return LumiCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events, color: AppColors.softYellow),
                const SizedBox(width: 8),
                Text(
                  'Top Performing Classes',
                  style: LumiTextStyles.h3().copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...topClasses.asMap().entries.map((entry) {
              final index = entry.key;
              final classModel = entry.value;
              final metrics = _classMetrics[classModel.id];
              final studentCount = _studentsByClass[classModel.id]?.length ?? 0;
              final totalMinutes = metrics?['totalMinutes'] ?? 0;
              final avgPerStudent =
                  studentCount > 0 ? (totalMinutes / studentCount).round() : 0;

              final medals = ['🥇', '🥈', '🥉'];
              final bgColors = [
                AppColors.softYellow.withValues(alpha: 0.1),
                AppColors.charcoal.withValues(alpha: 0.05),
                AppColors.warmOrange.withValues(alpha: 0.1),
              ];
              final borderColors = [
                AppColors.softYellow.withValues(alpha: 0.3),
                AppColors.charcoal.withValues(alpha: 0.2),
                AppColors.warmOrange.withValues(alpha: 0.3),
              ];

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgColors[index],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColors[index]),
                ),
                child: Row(
                  children: [
                    Text(
                      medals[index],
                      style: LumiTextStyles.body().copyWith(fontSize: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classModel.name,
                            style: LumiTextStyles.body().copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '$studentCount students',
                            style: LumiTextStyles.label(
                              color: AppColors.charcoal.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$avgPerStudent min',
                          style: LumiTextStyles.h3(
                            color: [
                              AppColors.rosePink,
                              AppColors.mintGreen,
                              AppColors.warmOrange
                            ][index % 3],
                          ),
                        ),
                        Text(
                          'per student',
                          style: LumiTextStyles.label(
                            color: AppColors.charcoal.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int? number) {
    if (number == null) return '0';
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final firebaseService =
          Provider.of<FirebaseService>(context, listen: false);

      // Fetch all classes for the school
      final classesSnapshot = await firebaseService.firestore
          .collection('classes')
          .where('schoolId', isEqualTo: widget.schoolId)
          .where('isActive', isEqualTo: true)
          .get();

      _classes = classesSnapshot.docs
          .map((doc) => ClassModel.fromFirestore(doc))
          .toList();

      // Fetch students for each class
      for (final classModel in _classes) {
        final studentDocs =
            await firebaseService.getStudentsInClass(classModel.id);
        _studentsByClass[classModel.id] =
            studentDocs.map((doc) => StudentModel.fromFirestore(doc)).toList();

        // Calculate metrics for this class
        int totalMinutes = 0;
        for (final student in _studentsByClass[classModel.id]!) {
          final logDocs = await firebaseService.getReadingLogsForStudent(
            student.id,
            startDate: _startDate,
            endDate: _endDate,
          );

          final logs =
              logDocs.map((doc) => ReadingLogModel.fromFirestore(doc)).toList();

          totalMinutes += logs.fold<int>(
            0,
            (sum, log) => sum + log.minutesRead,
          );
        }

        _classMetrics[classModel.id] = {
          'totalMinutes': totalMinutes,
        };
      }

      // Calculate school-wide metrics
      _calculateSchoolMetrics();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _calculateSchoolMetrics() {
    int totalStudents = 0;
    int activeStudents = 0;
    int totalMinutes = 0;
    int totalBooks = 0;
    int studentsMetTarget = 0;
    int studentsWithStreak = 0;
    int longestStreak = 0;
    final atRiskStudents = <Map<String, dynamic>>[];
    final weeklyMinutes = <String, int>{};

    for (final classModel in _classes) {
      final students = _studentsByClass[classModel.id] ?? [];
      totalStudents += students.length;

      for (final student in students) {
        if (student.stats != null) {
          final stats = student.stats!;

          if (stats.totalMinutesRead > 0) activeStudents++;
          totalMinutes += stats.totalMinutesRead;
          totalBooks += stats.totalBooksRead;

          if (stats.currentStreak > 0) studentsWithStreak++;
          if (stats.longestStreak > longestStreak) {
            longestStreak = stats.longestStreak;
          }

          // Check if student met target (simplified - would need more data)
          if (stats.averageMinutesPerDay >= 20) studentsMetTarget++;

          // Identify at-risk students
          if (stats.totalReadingDays < 3 ||
              stats.currentStreak == 0 ||
              stats.averageMinutesPerDay < 10) {
            atRiskStudents.add({
              'name': student.fullName,
              'className': classModel.name,
              'issue': stats.totalReadingDays < 3
                  ? 'Low engagement'
                  : 'Below target',
            });
          }
        }
      }
    }

    // Calculate weekly data (simplified)
    final weeks = (_endDate.difference(_startDate).inDays / 7).ceil();
    for (int i = 0; i < weeks; i++) {
      final weekStart = _startDate.add(Duration(days: i * 7));
      final weekLabel = DateFormat('MMM dd').format(weekStart);
      weeklyMinutes[weekLabel] = (totalMinutes / weeks).round();
    }

    final weeklyData = weeklyMinutes.entries
        .map((e) => {'label': e.key, 'minutes': e.value})
        .toList();

    final avgMinutesPerStudent =
        totalStudents > 0 ? totalMinutes / totalStudents : 0.0;
    final engagementRate =
        totalStudents > 0 ? (activeStudents / totalStudents) * 100 : 0.0;

    // Count classes above average
    int classesAboveAverage = 0;
    for (final classModel in _classes) {
      final students = _studentsByClass[classModel.id] ?? [];
      if (students.isEmpty) continue;

      final classMinutes = _classMetrics[classModel.id]?['totalMinutes'] ?? 0;
      final classAvg = classMinutes / students.length;

      if (classAvg > avgMinutesPerStudent) classesAboveAverage++;
    }

    _schoolMetrics = {
      'totalStudents': totalStudents,
      'activeStudents': activeStudents,
      'totalClasses': _classes.length,
      'totalMinutes': totalMinutes,
      'totalBooks': totalBooks,
      'avgMinutesPerStudent': avgMinutesPerStudent,
      'engagementRate': engagementRate,
      'studentsMetTarget': studentsMetTarget,
      'studentsWithStreak': studentsWithStreak,
      'longestStreak': longestStreak,
      'classesAboveAverage': classesAboveAverage,
      'atRiskStudents': atRiskStudents,
      'weeklyData': weeklyData,
    };
  }

  Future<void> _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadAnalyticsData();
    }
  }

  void _showAllAtRiskStudents(List<Map<String, dynamic>> students) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Students Needing Support'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: students.length,
            itemBuilder: (context, index) {
              final student = students[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.warmOrange.withValues(alpha: 0.2),
                  child: Text(
                    (student['name'] as String)[0].toUpperCase(),
                    style: LumiTextStyles.h3(color: AppColors.warmOrange),
                  ),
                ),
                title: Text(student['name'] as String),
                subtitle: Text(student['className'] as String),
                trailing: Text(student['issue'] as String),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
