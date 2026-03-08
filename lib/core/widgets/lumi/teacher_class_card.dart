import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Class Card
///
/// Card showing class name, student count badge, reading rate progress bar,
/// and a "View" chevron. Per spec: 16px radius, card shadow, progress bar.
class TeacherClassCard extends StatelessWidget {
  final String className;
  final int studentCount;
  final double readingRate;
  final VoidCallback? onTap;

  const TeacherClassCard({
    super.key,
    required this.className,
    required this.studentCount,
    required this.readingRate,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (readingRate * 100).round();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
          boxShadow: TeacherDimensions.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    className,
                    style: TeacherTypography.h3,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.teacherPrimaryLight,
                    borderRadius: BorderRadius.circular(TeacherDimensions.radiusRound),
                  ),
                  child: Text(
                    '$studentCount Students',
                    style: TeacherTypography.caption.copyWith(
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: readingRate.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.teacherPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '$percent% reading rate',
                  style: TeacherTypography.bodySmall,
                ),
                const Spacer(),
                Text(
                  'View',
                  style: TeacherTypography.bodySmall.copyWith(
                    color: AppColors.teacherPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.teacherPrimary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
