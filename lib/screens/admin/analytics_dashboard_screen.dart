import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/analytics_service.dart';
import '../../core/widgets/glass/glass_container.dart';

/// Administrator analytics dashboard showing school-wide reading insights
///
/// Features:
/// - Executive summary metrics
/// - Class comparison charts
/// - Daily reading trends
/// - Engagement heatmap (day of week)
/// - Top readers leaderboard
/// - Achievement distribution
/// - Growth indicators
class AnalyticsDashboardScreen extends StatefulWidget {
  final String schoolId;
  final String adminId;

  const AnalyticsDashboardScreen({
    super.key,
    required this.schoolId,
    required this.adminId,
  });

  @override
  State<AnalyticsDashboardScreen> createState() => _AnalyticsDashboardScreenState();
}

class _AnalyticsDashboardScreenState extends State<AnalyticsDashboardScreen> {
  final _analyticsService = AnalyticsService.instance;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  bool _isLoading = false;
  SchoolAnalytics? _analytics;
  List<DailyTrend>? _dailyTrends;
  EngagementHeatmap? _heatmap;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final analytics = await _analyticsService.getSchoolAnalytics(
        schoolId: widget.schoolId,
        startDate: _startDate,
        endDate: _endDate,
      );

      final trends = await _analyticsService.getDailyTrends(
        schoolId: widget.schoolId,
        startDate: _startDate,
        endDate: _endDate,
      );

      final heatmap = await _analyticsService.getEngagementHeatmap(
        schoolId: widget.schoolId,
        startDate: _startDate,
        endDate: _endDate,
      );

      setState(() {
        _analytics = analytics;
        _dailyTrends = trends;
        _heatmap = heatmap;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading analytics: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1976D2),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadAnalytics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Analytics Dashboard'),
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: _isLoading && _analytics == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header & Date Range
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '📊 School Analytics',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1976D2),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _selectDateRange,
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            '${DateFormat('MMM dd').format(_startDate)} - ${DateFormat('MMM dd').format(_endDate)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1976D2),
                            side: const BorderSide(color: Color(0xFF1976D2)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Executive Summary
                    if (_analytics != null) ...[
                      const Text(
                        '📈 Executive Summary',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildExecutiveSummary(_analytics!),
                      const SizedBox(height: 24),

                      // Growth Indicators
                      const Text(
                        '📊 Growth Metrics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildGrowthMetrics(_analytics!.growth),
                      const SizedBox(height: 24),

                      // Daily Trends Chart
                      if (_dailyTrends != null && _dailyTrends!.isNotEmpty) ...[
                        const Text(
                          '📈 Reading Trends',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTrendsChart(_dailyTrends!),
                        const SizedBox(height: 24),
                      ],

                      // Engagement Heatmap
                      if (_heatmap != null) ...[
                        const Text(
                          '🔥 Engagement by Day of Week',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildEngagementHeatmap(_heatmap!),
                        const SizedBox(height: 24),
                      ],

                      // Class Comparison
                      if (_analytics!.classMetrics.isNotEmpty) ...[
                        const Text(
                          '🏫 Class Performance',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildClassComparison(_analytics!.classMetrics),
                        const SizedBox(height: 24),
                      ],

                      // Top Readers
                      if (_analytics!.topReaders.isNotEmpty) ...[
                        const Text(
                          '🏆 Top 10 Readers',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildTopReaders(_analytics!.topReaders),
                        const SizedBox(height: 24),
                      ],

                      // Achievement Distribution
                      if (_analytics!.achievementDistribution.isNotEmpty) ...[
                        const Text(
                          '🎖️ Achievement Distribution',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildAchievementDistribution(_analytics!.achievementDistribution),
                      ],
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildExecutiveSummary(SchoolAnalytics analytics) {
    return GlassContainer(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  '👥',
                  'Total Students',
                  '${analytics.totalStudents}',
                  subtitle: '${analytics.activeStudents} active',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  '⏱️',
                  'Total Minutes',
                  '${analytics.totalMinutes}',
                  subtitle: '${analytics.avgMinutesPerStudent} avg/student',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  '📚',
                  'Books Read',
                  '${analytics.totalBooks}',
                  subtitle: '${analytics.avgBooksPerStudent} avg/student',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  '📊',
                  'Engagement',
                  '${analytics.engagementRate}%',
                  subtitle: 'Active participation',
                  color: _getEngagementColor(analytics.engagementRate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String emoji,
    String label,
    String value, {
    String? subtitle,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color ?? const Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF616161),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF9E9E9E),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGrowthMetrics(GrowthMetrics growth) {
    return GlassContainer(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildGrowthIndicator(
            'Minutes',
            growth.minutesGrowth,
            '⏱️',
          ),
          _buildGrowthIndicator(
            'Books',
            growth.booksGrowth,
            '📚',
          ),
          _buildGrowthIndicator(
            'Engagement',
            growth.engagementGrowth,
            '📊',
          ),
        ],
      ),
    );
  }

  Widget _buildGrowthIndicator(String label, int growth, String emoji) {
    final isPositive = growth >= 0;
    final color = isPositive ? const Color(0xFF4CAF50) : const Color(0xFFF44336);
    final icon = isPositive ? Icons.trending_up : Icons.trending_down;

    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              '${isPositive ? '+' : ''}$growth%',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF616161),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendsChart(List<DailyTrend> trends) {
    final spots = trends.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.minutesRead.toDouble());
    }).toList();

    final maxY = trends.isEmpty
        ? 100.0
        : trends.map((t) => t.minutesRead).reduce((a, b) => a > b ? a : b).toDouble();

    return GlassContainer(
      child: SizedBox(
        height: 250,
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: const Color(0xFFE0E0E0),
                  strokeWidth: 1,
                );
              },
            ),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval: trends.length > 7 ? (trends.length / 7).ceilToDouble() : 1,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= trends.length) return const Text('');
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('M/d').format(trends[index].date),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF616161)),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  interval: maxY / 5,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10, color: Color(0xFF616161)),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (trends.length - 1).toDouble(),
            minY: 0,
            maxY: maxY * 1.1,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: const Color(0xFF1976D2),
                barWidth: 3,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: const Color(0xFF1976D2).withOpacity(0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEngagementHeatmap(EngagementHeatmap heatmap) {
    return GlassContainer(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final count = heatmap.counts[index];
              final intensity = heatmap.maxCount > 0 ? count / heatmap.maxCount : 0.0;
              final color = Color.lerp(
                const Color(0xFFE3F2FD),
                const Color(0xFF1976D2),
                intensity,
              )!;

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      heatmap.dayLabels[index],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF616161),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 80,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$count',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: intensity > 0.5 ? Colors.white : const Color(0xFF424242),
                              ),
                            ),
                            Text(
                              'logs',
                              style: TextStyle(
                                fontSize: 10,
                                color: intensity > 0.5 ? Colors.white70 : const Color(0xFF616161),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${heatmap.minutes[index]} min',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9E9E9E),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildClassComparison(List<ClassMetric> classMetrics) {
    return GlassContainer(
      child: Column(
        children: classMetrics.take(5).map((classMetric) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        classMetric.className,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${classMetric.totalMinutes} min',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: classMetric.totalMinutes / (classMetrics.first.totalMinutes > 0 ? classMetrics.first.totalMinutes : 1),
                        backgroundColor: const Color(0xFFE0E0E0),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF1976D2)),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${classMetric.activeStudents}/${classMetric.totalStudents} active',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF616161),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopReaders(List<TopReader> topReaders) {
    return GlassContainer(
      child: Column(
        children: topReaders.asMap().entries.map((entry) {
          final rank = entry.key + 1;
          final reader = entry.value;
          final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: Text(
                    medal.isEmpty ? '$rank.' : medal,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reader.studentName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        reader.className,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${reader.minutesRead} min',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAchievementDistribution(Map<String, int> distribution) {
    final rarities = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
    final colors = {
      'common': const Color(0xFFCD7F32), // Bronze
      'uncommon': const Color(0xFFC0C0C0), // Silver
      'rare': const Color(0xFFFFD700), // Gold
      'epic': const Color(0xFF9C27B0), // Purple
      'legendary': const Color(0xFFFF6B6B), // Rainbow/Red
    };

    return GlassContainer(
      child: Column(
        children: rarities.map((rarity) {
          final count = distribution[rarity] ?? 0;
          final total = distribution.values.fold(0, (sum, val) => sum + val);
          final percentage = total > 0 ? (count / total * 100).round() : 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors[rarity],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: Text(
                    rarity[0].toUpperCase() + rarity.substring(1),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: total > 0 ? count / total : 0,
                    backgroundColor: const Color(0xFFE0E0E0),
                    valueColor: AlwaysStoppedAnimation(colors[rarity]),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$count ($percentage%)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF616161),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getEngagementColor(int engagementRate) {
    if (engagementRate >= 70) return const Color(0xFF4CAF50); // Green
    if (engagementRate >= 50) return const Color(0xFFFFA726); // Orange
    return const Color(0xFFF44336); // Red
  }
}
