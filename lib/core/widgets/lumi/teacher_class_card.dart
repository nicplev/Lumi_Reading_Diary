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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        child: Container(
          padding: const EdgeInsets.all(TeacherDimensions.paddingXL),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
            border: Border.all(color: AppColors.teacherBorder),
            boxShadow: TeacherDimensions.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Classroom',
                          style: TeacherTypography.caption.copyWith(
                            color: AppColors.teacherPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          className,
                          style: TeacherTypography.h3,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.teacherSurfaceTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.teacherPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherPrimaryLight,
                      borderRadius: BorderRadius.circular(
                        TeacherDimensions.radiusRound,
                      ),
                    ),
                    child: Text(
                      '$studentCount Students',
                      style: TeacherTypography.caption.copyWith(
                        color: AppColors.teacherPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.teacherSurfaceTint,
                      borderRadius: BorderRadius.circular(
                        TeacherDimensions.radiusRound,
                      ),
                    ),
                    child: Text(
                      '$percent% reading rate',
                      style: TeacherTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: readingRate.clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: AppColors.teacherSurfaceTint,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.teacherPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
