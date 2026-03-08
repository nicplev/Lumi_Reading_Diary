import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Tier Section
///
/// Color dot + level name + book count header, followed by a 3-column grid.
/// Per spec: 12px color circle, 16px level text, 13px count text.
class TeacherTierSection extends StatelessWidget {
  final int level;
  final String name;
  final Color color;
  final int bookCount;
  final List<Widget> bookItems;

  const TeacherTierSection({
    super.key,
    required this.level,
    required this.name,
    required this.color,
    required this.bookCount,
    required this.bookItems,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Level $level - $name',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($bookCount books)',
              style: TeacherTypography.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 3-column grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
          children: bookItems,
        ),
      ],
    );
  }
}
