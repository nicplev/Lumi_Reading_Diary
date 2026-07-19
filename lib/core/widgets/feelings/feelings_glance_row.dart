import 'package:flutter/material.dart';

import '../../../data/models/reading_log_model.dart';
import '../../feelings/feeling_aggregator.dart';
import '../../feelings/feeling_scale.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import '../../../core/utils/image_decode.dart';

/// The "at a glance" row — one tile per day showing the blob character for that
/// day's feeling. Days with no recorded feeling show a neutral dashed
/// placeholder and an em-dash instead of a number (never a zero or a blob).
class FeelingsGlanceRow extends StatelessWidget {
  final List<FeelingBucket> buckets;

  const FeelingsGlanceRow({super.key, required this.buckets});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final bucket in buckets)
          Expanded(child: _Tile(bucket: bucket)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final FeelingBucket bucket;

  const _Tile({required this.bucket});

  @override
  Widget build(BuildContext context) {
    final feeling =
        bucket.hasValue ? feelingFromValue(bucket.value!.round()) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Text(
            bucket.label,
            style: TeacherTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: feeling == null
                ? _placeholder()
                : _blob(context, feeling),
          ),
          const SizedBox(height: 6),
          // Feeling word (e.g. "Good") rather than its 1–5 number. scaleDown
          // keeps the longest label ("Tricky") from overflowing the narrow
          // per-day tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              feeling?.label ?? '—',
              style: TeacherTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: feeling == null
                    ? AppColors.textSecondary.withValues(alpha: 0.6)
                    : AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(BuildContext context, ReadingFeeling feeling) {
    return Container(
      decoration: BoxDecoration(
        color: feeling.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(6),
      child: Image.asset(
        feeling.asset,
        fit: BoxFit.contain,
        cacheWidth: decodeCacheSize(context, 32),
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            feeling.label[0],
            style: TeacherTypography.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: feeling.color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.teacherBorder.withValues(alpha: 0.25),
        border: Border.all(
          color: AppColors.teacherBorder,
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.remove_rounded,
          size: 16,
          color: AppColors.textSecondary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
