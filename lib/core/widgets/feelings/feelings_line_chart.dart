import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../feelings/feeling_aggregator.dart';
import '../../feelings/feeling_scale.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Line chart of average daily feeling on a fixed 1–5 scale.
///
/// Buckets without a recorded feeling render as gaps (no point, broken line) —
/// never as zero. See [FeelingBucket].
class FeelingsLineChart extends StatelessWidget {
  final List<FeelingBucket> buckets;
  final Color lineColor;

  const FeelingsLineChart({
    super.key,
    required this.buckets,
    this.lineColor = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < buckets.length; i++)
        buckets[i].hasValue
            ? FlSpot(i.toDouble(), buckets[i].value!)
            : FlSpot.nullSpot,
    ];

    return SizedBox(
      height: 200,
      // Right inset so the last x-axis label (e.g. "Sun") isn't clipped at the
      // card edge — the plot otherwise ran flush to the right.
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (buckets.length - 1).toDouble(),
          minY: 0.75,
          maxY: 5.25,
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: lineColor,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: spot.y.isNaN ? 0 : 4,
                  color: lineColor,
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.1),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 46,
                getTitlesWidget: _leftTitle,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 22,
                getTitlesWidget: _bottomTitle,
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            checkToShowHorizontalLine: (v) => v >= 1 && v <= 5,
            getDrawingHorizontalLine: (v) => FlLine(
              color: AppColors.teacherBorder.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _leftTitle(double value, TitleMeta meta) {
    // Only label exact gridline values. fl_chart also samples the padded
    // min/max edges (e.g. 5.25), whose toInt() rounded to 5 and rendered a
    // duplicate 'Great' overlapping the top label.
    final v = value.round();
    if ((value - v).abs() > 0.001) return const SizedBox.shrink();
    final tier = feelingTierByValue[v];
    if (tier == null) return const SizedBox.shrink();
    // Feelings are categorical, so the description alone is clearer than a
    // 1–5 numeral — the number is dropped entirely.
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        tier,
        textAlign: TextAlign.right,
        style: TeacherTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _bottomTitle(double value, TitleMeta meta) {
    final i = value.round();
    if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
    // Avoid crowding the all-time axis: every bucket for week/month, but the
    // bottom titles interval already limits this to whole indices.
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        buckets[i].label,
        style: TeacherTypography.caption.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}
