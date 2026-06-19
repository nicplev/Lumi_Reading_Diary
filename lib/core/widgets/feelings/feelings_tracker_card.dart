import 'package:flutter/material.dart';

import '../../../data/models/reading_log_model.dart';
import '../../feelings/feeling_aggregator.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'feelings_glance_row.dart';
import 'feelings_line_chart.dart';

/// Student-profile graphic showing how a child has felt about their reading
/// over time, using the blob feeling characters.
///
/// Renders two stacked cards:
///  1. A 1–5 line chart of average daily feeling, with a period selector.
///  2. A per-day "at a glance" blob row (week view only).
///
/// Edge cases handled by [aggregateFeelings]:
///  - Quick logs (home-screen widget / parent dashboard) with no feeling, and
///    days with no log at all, render as gaps / neutral tiles — never zero.
///  - Multiple logs in a day are averaged.
///  - A whole-history with no feelings shows a friendly empty state.
class FeelingsTrackerCard extends StatefulWidget {
  final List<ReadingLogModel> logs;

  /// Accent colour for the line + headers. Defaults to the success green seen in
  /// the reference design; pass a parent accent for parent surfaces.
  final Color accentColor;

  /// Injectable clock for tests.
  final DateTime? now;

  const FeelingsTrackerCard({
    super.key,
    required this.logs,
    this.accentColor = LumiTokens.green,
    this.now,
  });

  @override
  State<FeelingsTrackerCard> createState() => _FeelingsTrackerCardState();
}

class _FeelingsTrackerCardState extends State<FeelingsTrackerCard> {
  FeelingPeriod _period = FeelingPeriod.week;

  @override
  Widget build(BuildContext context) {
    final series =
        aggregateFeelings(widget.logs, period: _period, now: widget.now);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 16),
          if (!series.hasAnyFeeling)
            _emptyState()
          else ...[
            FeelingsLineChart(
              buckets: series.buckets,
              lineColor: widget.accentColor,
            ),
            // Per-day feeling blobs live in the same card, under the trend —
            // one card instead of two near-duplicate ones.
            if (series.showGlance) ...[
              const SizedBox(height: 16),
              const Divider(height: 1, color: LumiTokens.rule),
              const SizedBox(height: 16),
              FeelingsGlanceRow(buckets: series.buckets),
            ],
          ],
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            'Reading Feelings',
            style: LumiType.subhead,
          ),
        ),
        _periodSelector(),
      ],
    );
  }

  Widget _periodSelector() {
    return PopupMenuButton<FeelingPeriod>(
      initialValue: _period,
      onSelected: (p) => setState(() => _period = p),
      tooltip: 'Change period',
      // Match the app's rounded, bordered surfaces instead of the default
      // Material menu.
      color: LumiTokens.paper,
      surfaceTintColor: LumiTokens.paper,
      elevation: 3,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
        side: const BorderSide(color: LumiTokens.rule),
      ),
      itemBuilder: (_) => [
        for (final p in FeelingPeriod.values)
          PopupMenuItem(
            value: p,
            height: 42,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.label,
                    style: LumiType.caption.copyWith(
                      fontWeight:
                          p == _period ? FontWeight.w700 : FontWeight.w500,
                      color: p == _period
                          ? LumiTokens.ink
                          : LumiTokens.muted,
                    ),
                  ),
                ),
                if (p == _period)
                  const Icon(Icons.check_rounded,
                      size: 16, color: LumiTokens.ink),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: LumiTokens.cream,
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          border: Border.all(color: LumiTokens.rule),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _period.label,
              style: LumiType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: LumiTokens.ink,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.sentiment_satisfied_alt_rounded,
              size: 32,
              color: LumiTokens.muted.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              'No reading feelings recorded yet',
              style: LumiType.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: child,
    );
  }
}
