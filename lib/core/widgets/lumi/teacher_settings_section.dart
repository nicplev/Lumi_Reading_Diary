import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Settings Section
///
/// Grouped settings with gray header bar (uppercase) and items below.
/// Per spec: 16px radius, gray bg header, uppercase 13px title.
class TeacherSettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const TeacherSettingsSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppColors.background,
            ),
            child: Text(
              title.toUpperCase(),
              style: TeacherTypography.sectionHeader,
            ),
          ),
          // Items with dividers
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}
