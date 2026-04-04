import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Alert banner type for teacher/admin screens
enum AlertBannerType {
  warning,
  success,
  info,
}

/// Lumi Design System - Teacher Alert Banner
///
/// Left-border accent banner for warnings and success messages.
/// Per style preview: 4px left border, rounded right corners only.
class TeacherAlertBanner extends StatelessWidget {
  final AlertBannerType type;
  final String message;
  final String? emoji;

  const TeacherAlertBanner({
    super.key,
    required this.type,
    required this.message,
    this.emoji,
  });

  Color get _accentColor {
    switch (type) {
      case AlertBannerType.warning:
        return AppColors.warmOrange;
      case AlertBannerType.success:
        return AppColors.success;
      case AlertBannerType.info:
        return AppColors.teacherPrimary;
    }
  }

  Color get _backgroundColor {
    switch (type) {
      case AlertBannerType.warning:
        return const Color(0xFFFFF7EC);
      case AlertBannerType.success:
        return const Color(0xFFE9F7EF);
      case AlertBannerType.info:
        return AppColors.teacherPrimaryLight;
    }
  }

  IconData get _icon {
    switch (type) {
      case AlertBannerType.warning:
        return Icons.warning_amber_rounded;
      case AlertBannerType.success:
        return Icons.check_circle_rounded;
      case AlertBannerType.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _accentColor.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.08),
            blurRadius: 18,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: emoji != null
                  ? Text(
                      emoji!,
                      style: const TextStyle(fontSize: 14),
                    )
                  : Icon(
                      _icon,
                      size: 16,
                      color: _accentColor,
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
