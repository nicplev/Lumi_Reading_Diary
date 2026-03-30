import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class TeacherReadingLevelPill extends StatelessWidget {
  const TeacherReadingLevelPill({
    super.key,
    required this.label,
    this.onTap,
    this.isUnset = false,
    this.isUnresolved = false,
    this.levelColor,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isUnset;
  final bool isUnresolved;
  final Color? levelColor;

  @override
  Widget build(BuildContext context) {
    final colors = _colors();
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.foreground,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: colors.foreground,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: content,
      ),
    );
  }

  _PillColors _colors() {
    if (isUnresolved) {
      return _PillColors(
        background: AppColors.error.withValues(alpha: 0.08),
        border: AppColors.error.withValues(alpha: 0.18),
        foreground: AppColors.error,
      );
    }

    if (isUnset) {
      return _PillColors(
        background: AppColors.warmOrange.withValues(alpha: 0.10),
        border: AppColors.warmOrange.withValues(alpha: 0.18),
        foreground: AppColors.warmOrange,
      );
    }

    if (levelColor != null) {
      return _PillColors(
        background: levelColor!.withValues(alpha: 0.12),
        border: levelColor!.withValues(alpha: 0.25),
        foreground: levelColor!,
      );
    }

    return _PillColors(
      background: AppColors.teacherSurfaceTint,
      border: AppColors.teacherBorder,
      foreground: AppColors.teacherPrimary,
    );
  }
}

class _PillColors {
  const _PillColors({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}
