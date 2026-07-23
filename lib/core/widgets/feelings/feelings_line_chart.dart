import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../feelings/feeling_aggregator.dart';
import '../../feelings/feeling_scale.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Line chart of daily feeling on a fixed 1–5 scale (lowest feeling per day,
/// averaged across days in coarser buckets — see [FeelingBucket]).
///
/// Buckets without a recorded feeling render as gaps (no point, broken line) —
/// never as zero. See [FeelingBucket].
class FeelingsLineChart extends StatelessWidget {
  final List<FeelingBucket> buckets;
  final Color lineColor;

  const FeelingsLineChart({
    super.key,
    required this.buckets,
    this.lineColor = LumiTokens.ink,
  });

  /// Approx rendered width of a bottom label (e.g. "Aug") at caption size,
  /// including breathing room, used to decide how many fit without overlapping.
  static const double _approxLabelWidth = 34;

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // How many labels fit across the plot without overlapping, then the
            // stride that thins the axis to that many. Prevents the 12 all-time
            // months colliding into "AugSepOct…" on narrow devices, while week
            // (7) and month (~5) always show every label.
            final plotWidth = (constraints.maxWidth - 66).clamp(1.0, 4000.0);
            final maxLabels =
                (plotWidth / _approxLabelWidth).floor().clamp(2, buckets.length);
            final stride = buckets.isEmpty
                ? 1
                : (buckets.length / maxLabels).ceil().clamp(1, buckets.length);
            return LineChart(
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
                  radius: spot.y.isNaN ? 0 : 6,
                  color: _dotColor(spot.y),
                  strokeWidth: 2,
                  strokeColor: LumiTokens.paper,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 56,
                getTitlesWidget: _leftTitle,
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 22,
                getTitlesWidget: (v, m) => _bottomTitle(v, m, stride),
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
              color: LumiTokens.rule,
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
          ),
        ),
            );
          },
        ),
      ),
    );
  }

  /// Each marker carries its feeling's canonical colour (matching the blobs),
  /// while the connecting line stays neutral — so colour reads as meaning.
  Color _dotColor(double y) {
    if (y.isNaN) return lineColor;
    final feeling = feelingFromValue(y.round().clamp(1, 5));
    return feeling?.color ?? lineColor;
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
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: LumiType.caption.copyWith(
          color: LumiTokens.muted,
        ),
      ),
    );
  }

  Widget _bottomTitle(double value, TitleMeta meta, int stride) {
    final i = value.round();
    if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
    // Show every `stride`-th label, but always the first and last so the range
    // stays legible. `stride == 1` (week/month) shows them all.
    final isLast = i == buckets.length - 1;
    if (i % stride != 0 && !isLast) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        buckets[i].label,
        style: LumiType.caption.copyWith(
          color: LumiTokens.muted,
        ),
      ),
    );
  }
}
