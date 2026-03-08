import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';

/// Pre-written parent comment templates displayed as selectable chips.
/// Multiple chips can be selected; their text is concatenated for the
/// final parent comment saved to the reading log.
class CommentChips extends StatelessWidget {
  final List<String> selectedComments;
  final ValueChanged<List<String>> onCommentsChanged;

  const CommentChips({
    super.key,
    required this.selectedComments,
    required this.onCommentsChanged,
  });

  static const _commentCategories = {
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
          'Select any that apply (optional)',
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 20),
        ..._commentCategories.entries.map((entry) {
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
                    return _CommentChip(
                      label: comment,
                      isSelected: isSelected,
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
  final VoidCallback onTap;

  const _CommentChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }
}
