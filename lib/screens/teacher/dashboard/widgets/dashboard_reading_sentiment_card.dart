import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/teacher_constants.dart';
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

  static Color _feelingColor(ReadingFeeling f) {
    return switch (f) {
      ReadingFeeling.great => AppColors.success,
      ReadingFeeling.good => AppColors.mintGreen,
      ReadingFeeling.okay => const Color(0xFFE0C85A),
      ReadingFeeling.tricky => AppColors.warmOrange,
      ReadingFeeling.hard => AppColors.error,
    };
  }

  // Darker text-safe versions of each feeling color for readable labels
  static Color _feelingTextColor(ReadingFeeling f) {
    return switch (f) {
      ReadingFeeling.great => AppColors.success,
      ReadingFeeling.good => const Color(0xFF4A8A3A),
      ReadingFeeling.okay => const Color(0xFF9A8220),
      ReadingFeeling.tricky => AppColors.warmOrange,
      ReadingFeeling.hard => AppColors.error,
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
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reading Sentiment',
                  style: TeacherTypography.sectionHeader
                      .copyWith(color: AppColors.teacherPrimary)),
              Text('This week', style: TeacherTypography.caption),
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
                  color: _feelingColor(mostCommon).withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(TeacherDimensions.radiusS),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/blobs/blob-${mostCommon.name}.png',
                      width: 18,
                      height: 18,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Most common: ${_feelingLabel(mostCommon)}',
                      style: TeacherTypography.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _feelingTextColor(mostCommon),
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
            child: Image.asset(
              'assets/blobs/blob-${feeling.name}.png',
              errorBuilder: (_, __, ___) => Icon(
                Icons.sentiment_neutral_rounded,
                size: 20,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Label
          SizedBox(
            width: 48,
            child: Text(
              _feelingLabel(feeling),
              style: TeacherTypography.caption
                  .copyWith(fontWeight: FontWeight.w600),
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
                backgroundColor: color.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                    color.withValues(alpha: 0.7)),
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
              style: TeacherTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
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
                color: AppColors.textSecondary.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              'No reading feelings shared yet this week',
              style: TeacherTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
