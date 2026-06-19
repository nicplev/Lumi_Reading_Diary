import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Total chips a parent can select across all sections. Capped so the
/// teacher-side displays (which render the chips in tight rows next to the
/// feeling blob) stay on one line and don't wrap into a cluttered stack.
const int kMaxParentCommentChips = 3;

/// Pre-written parent comment templates displayed as selectable chips.
/// Multiple chips can be selected; their text is concatenated for the
/// final parent comment saved to the reading log.
class CommentChips extends StatelessWidget {
  final List<String> selectedComments;
  final ValueChanged<List<String>> onCommentsChanged;
  final Map<String, List<String>>? categories;
  final int maxSelections;

  const CommentChips({
    super.key,
    required this.selectedComments,
    required this.onCommentsChanged,
    this.categories,
    this.maxSelections = kMaxParentCommentChips,
  });

  static const defaultCommentCategories = {
    'Encouragement': [
      'Great job!',
      'Keep it up!',
      'Loved hearing you read!',
      'So proud of you!',
    ],
    'Reading Skills': [
      'Sounded out words well',
      'Good finger tracking',
      'Read with expression',
      'Used picture clues',
    ],
    'Comprehension': [
      'Understood the story well',
      'Asked great questions',
      'Made predictions',
      'Retold the story',
    ],
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How did it go?',
          style: LumiTextStyles.h2(),
        ),
        const SizedBox(height: 8),
        Text(
          'Select up to $maxSelections that apply (optional)',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 20),
        ...(categories ?? defaultCommentCategories).entries.map((entry) {
          final atLimit = selectedComments.length >= maxSelections;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: LumiTextStyles.label(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((comment) {
                    final isSelected = selectedComments.contains(comment);
                    final enabled = isSelected || !atLimit;
                    return _CommentChip(
                      label: comment,
                      isSelected: isSelected,
                      enabled: enabled,
                      onTap: () {
                        final updated = List<String>.from(selectedComments);
                        if (isSelected) {
                          updated.remove(comment);
                        } else {
                          updated.add(comment);
                        }
                        onCommentsChanged(updated);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _CommentChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _CommentChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.mintGreen
                : const Color(0xFFF5F5F7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFA5D6A7)
                  : const Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(
                  Icons.check,
                  size: 14,
                  color: AppColors.charcoal.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: LumiTextStyles.bodySmall(
                  color: AppColors.charcoal,
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
