import 'package:flutter/material.dart';

import '../../../data/models/reading_log_model.dart';
import '../../feelings/feeling_aggregator.dart';
import '../../feelings/feeling_scale.dart';
import '../../../core/utils/image_decode.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

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
        for (final bucket in buckets) Expanded(child: _Tile(bucket: bucket)),
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
            style: LumiType.caption.copyWith(
              color: LumiTokens.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: feeling == null
                ? _placeholder()
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: _blob(context, feeling)),
                      // Multiple sessions that day: the blob shows the LOWEST
                      // feeling, so mark that it's one of several rather than the
                      // whole story.
                      if (bucket.feelingCount > 1)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: _multiSessionBadge(bucket.feelingCount),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 6),
          // Feeling word (e.g. "Good") rather than its 1–5 number. scaleDown
          // keeps the longest label ("Tricky") from overflowing the narrow
          // per-day tile.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              feeling?.label ?? '—',
              style: LumiType.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: feeling == null
                    ? LumiTokens.muted.withValues(alpha: 0.6)
                    : LumiTokens.ink,
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
            style: LumiType.caption.copyWith(
              fontWeight: FontWeight.w800,
              color: feeling.color,
            ),
          ),
        ),
      ),
    );
  }

  /// Small count badge shown on a day with more than one logged feeling.
  Widget _multiSessionBadge(int count) {
    return Container(
      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: LumiTokens.rule),
      ),
      child: Center(
        child: Text(
          '$count',
          style: LumiType.caption.copyWith(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w800,
            color: LumiTokens.muted,
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: LumiTokens.cream,
        border: Border.all(
          color: LumiTokens.rule,
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.remove_rounded,
          size: 16,
          color: LumiTokens.muted.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
