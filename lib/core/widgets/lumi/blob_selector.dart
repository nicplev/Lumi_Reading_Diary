import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../data/models/reading_log_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// A widget that displays 5 blob characters for the child to rate
/// how the reading session felt. Maps to [ReadingFeeling] enum.
class BlobSelector extends StatefulWidget {
  final ReadingFeeling? selectedFeeling;
  final ValueChanged<ReadingFeeling> onFeelingSelected;

  const BlobSelector({
    super.key,
    this.selectedFeeling,
    required this.onFeelingSelected,
  });

  @override
  State<BlobSelector> createState() => _BlobSelectorState();
}

class _BlobSelectorState extends State<BlobSelector> {
  ReadingFeeling? _hoveredFeeling;

  static const _blobData = [
    _BlobOption(
      feeling: ReadingFeeling.hard,
      asset: 'assets/blobs/blob-hard.png',
      label: 'Hard',
      color: Color(0xFF6FA8DC),
    ),
    _BlobOption(
      feeling: ReadingFeeling.tricky,
      asset: 'assets/blobs/blob-tricky.png',
      label: 'Tricky',
      color: Color(0xFF7CB97C),
    ),
    _BlobOption(
      feeling: ReadingFeeling.okay,
      asset: 'assets/blobs/blob-okay.png',
      label: 'Okay',
      color: Color(0xFFE8C547),
    ),
    _BlobOption(
      feeling: ReadingFeeling.good,
      asset: 'assets/blobs/blob-good.png',
      label: 'Good',
      color: Color(0xFFF5A347),
    ),
    _BlobOption(
      feeling: ReadingFeeling.great,
      asset: 'assets/blobs/blob-great.png',
      label: 'Great!',
      color: Color(0xFFE86B6B),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'How did reading feel?',
          style: LumiTextStyles.h2(),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Let your child choose',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _blobData.map((blob) => _buildBlobItem(blob)).toList(),
        ),
      ],
    );
  }

  Widget _buildBlobItem(_BlobOption blob) {
    final isSelected = widget.selectedFeeling == blob.feeling;
    final isHovered = _hoveredFeeling == blob.feeling;
    final isActive = isSelected || isHovered;

    return GestureDetector(
      onTap: () => widget.onFeelingSelected(blob.feeling),
      onTapDown: (_) => setState(() => _hoveredFeeling = blob.feeling),
      onTapUp: (_) => setState(() => _hoveredFeeling = null),
      onTapCancel: () => setState(() => _hoveredFeeling = null),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isSelected
                  ? 1.35
                  : isHovered
                      ? 1.15
                      : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 56,
                height: 64,
                child: Image.asset(
                  blob.asset,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      color: blob.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        blob.label[0],
                        style: LumiTextStyles.h2(color: blob.color),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: isSelected ? 28 : 6,
            ),
            Text(
              blob.label,
              style: LumiTextStyles.caption(
                color: isSelected
                    ? blob.color
                    : AppColors.charcoal.withValues(alpha: 0.7),
              ).copyWith(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ).animate(
      target: isActive ? 1 : 0,
    );
  }
}

class _BlobOption {
  final ReadingFeeling feeling;
  final String asset;
  final String label;
  final Color color;

  const _BlobOption({
    required this.feeling,
    required this.asset,
    required this.label,
    required this.color,
  });
}
