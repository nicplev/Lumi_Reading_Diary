import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Alert banner type for teacher/admin screens
enum AlertBannerType {
  warning,
  success,
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
    }
  }

  Color get _backgroundColor {
    switch (type) {
      case AlertBannerType.warning:
        return const Color(0xFFFFF7EC);
      case AlertBannerType.success:
        return const Color(0xFFE9F7EF);
    }
  }

  IconData get _icon {
    switch (type) {
      case AlertBannerType.warning:
        return Icons.warning_amber_rounded;
      case AlertBannerType.success:
        return Icons.check_circle_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(24),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: emoji != null
                  ? Text(
                      emoji!,
                      style: const TextStyle(fontSize: 18),
                    )
                  : Icon(
                      _icon,
                      size: 22,
                      color: _accentColor,
                    ),
            ),
          ),
          const SizedBox(width: 12),
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
