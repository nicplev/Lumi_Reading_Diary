import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';

/// Lumi Design System - Teacher Settings Item
///
/// 36x36 icon box + label + trailing (arrow or toggle).
/// Per spec: 10px icon box radius, 18px icon, 15px label.
class TeacherSettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color? iconColor;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TeacherSettingsItem({
    super.key,
    required this.icon,
    required this.iconBgColor,
    this.iconColor,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TeacherDimensions.paddingL,
          vertical: TeacherDimensions.paddingM,
        ),
        child: Row(
          children: [
            // Icon box
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: TeacherDimensions.iconS,
                color: iconColor ?? AppColors.white,
              ),
            ),
            const SizedBox(width: 12),
            // Label
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.charcoal,
                ),
              ),
            ),
            // Trailing
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
          ],
        ),
      ),
    );
  }
}
