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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: TeacherTypography.sectionHeader,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            border: Border.all(color: AppColors.teacherBorder),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                items[i],
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: AppColors.teacherBorder.withValues(alpha: 0.9),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
