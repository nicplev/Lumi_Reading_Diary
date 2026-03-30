import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Stat Card
///
/// Compact stat display with colored icon container, value, and label.
/// Per style preview: 16px radius, 40x40 icon, 28px value, 12px label.
class TeacherStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String value;
  final String label;

  const TeacherStatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final intValue = int.tryParse(value);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusXL),
        border: Border.all(color: AppColors.teacherBorder),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 24,
              color: iconColor,
            ),
          ),
          const SizedBox(height: 16),
          if (intValue != null)
            TweenAnimationBuilder<int>(
              tween: IntTween(begin: 0, end: intValue),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeOutCubic,
              builder: (context, val, child) {
                return Text(
                  val.toString(),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: AppColors.charcoal,
                    height: 1,
                  ),
                );
              },
            )
          else
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.charcoal,
                height: 1,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
