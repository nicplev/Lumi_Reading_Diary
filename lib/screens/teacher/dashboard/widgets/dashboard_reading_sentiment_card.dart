import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../data/models/reading_log_model.dart';

/// Shows the distribution of child reading feelings (hard → great) this week.
class DashboardReadingSentimentCard extends StatelessWidget {
  final List<ReadingLogModel> weeklyLogs;

  const DashboardReadingSentimentCard({
    super.key,
    required this.weeklyLogs,
  });

  static const _feelingOrder = [
    ReadingFeeling.great,
    ReadingFeeling.good,
    ReadingFeeling.okay,
    ReadingFeeling.tricky,
    ReadingFeeling.hard,
  ];

  // Each feeling's bar hue echoes its blob art: red(great) → orange(good) →
  // yellow(okay) → green(tricky) → blue(hard). Matches feeling_scale.dart order.
  static Color _feelingColor(ReadingFeeling f) {
    return switch (f) {
      ReadingFeeling.great => LumiTokens.red,
      ReadingFeeling.good => LumiTokens.orange,
      ReadingFeeling.okay => LumiTokens.yellow,
      ReadingFeeling.tricky => LumiTokens.green,
      ReadingFeeling.hard => LumiTokens.blue,
    };
  }

  static String _feelingLabel(ReadingFeeling f) {
    return switch (f) {
      ReadingFeeling.great => 'Great',
      ReadingFeeling.good => 'Good',
      ReadingFeeling.okay => 'Okay',
      ReadingFeeling.tricky => 'Tricky',
      ReadingFeeling.hard => 'Hard',
    };
  }

  @override
  Widget build(BuildContext context) {
    // Count feelings
    final counts = <ReadingFeeling, int>{};
    for (final log in weeklyLogs) {
      if (log.childFeeling != null) {
        counts.update(log.childFeeling!, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    final totalWithFeeling = counts.values.fold<int>(0, (a, b) => a + b);
    final maxCount =
        counts.values.fold<int>(0, (a, b) => math.max(a, b));

    // Find most common feeling
    ReadingFeeling? mostCommon;
    if (counts.isNotEmpty) {
      mostCommon = counts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }

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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reading Sentiment',
                  style: LumiType.subhead.copyWith(color: LumiTokens.blue)),
              Text('This week', style: LumiType.caption),
            ],
          ),
          const SizedBox(height: 16),

          if (totalWithFeeling == 0)
            _buildEmptyState()
          else ...[
            ..._feelingOrder.map((f) => _buildBar(
                  feeling: f,
                  count: counts[f] ?? 0,
                  maxCount: maxCount,
                )),
            const SizedBox(height: 12),
            // Footer: most common
            if (mostCommon != null)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _feelingColor(mostCommon).withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(LumiTokens.radiusSmall),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/blobs/blob-${mostCommon.name}.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Most common: ${_feelingLabel(mostCommon)}',
                      style: LumiType.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: LumiTokens.ink,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildBar({
    required ReadingFeeling feeling,
    required int count,
    required int maxCount,
  }) {
    final fraction = maxCount > 0 ? count / maxCount : 0.0;
    final color = _feelingColor(feeling);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Blob image
          SizedBox(
            width: 24,
            height: 24,
            child: Padding(
              // The "hard" blob art sits larger in its canvas than the others;
              // a small inset keeps all five blobs visually the same size.
              padding: EdgeInsets.all(feeling == ReadingFeeling.hard ? 2.5 : 0),
              child: Image.asset(
                'assets/blobs/blob-${feeling.name}.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.sentiment_neutral_rounded,
                  size: 20,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Label
          SizedBox(
            width: 48,
            child: Text(
              _feelingLabel(feeling),
              style: LumiType.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: LumiTokens.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Bar
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                backgroundColor: LumiTokens.rule,
                valueColor:
                    AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Count
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: LumiType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: LumiTokens.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.sentiment_satisfied_alt_rounded,
                size: 32,
                color: LumiTokens.muted.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'No reading feelings shared yet this week',
              style: LumiType.caption,
            ),
          ],
        ),
      ),
    );
  }
}
