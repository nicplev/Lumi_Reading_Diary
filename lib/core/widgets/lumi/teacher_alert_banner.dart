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

  Color get _borderColor {
    switch (type) {
      case AlertBannerType.warning:
        return const Color(0xFFFFCC80);
      case AlertBannerType.success:
        return const Color(0xFFA5D6A7);
    }
  }

  Color get _backgroundColor {
    switch (type) {
      case AlertBannerType.warning:
        return const Color(0xFFFFF3E0);
      case AlertBannerType.success:
        return const Color(0xFFE8F5E9);
    }
  }

  String get _defaultEmoji {
    switch (type) {
      case AlertBannerType.warning:
        return '\u26A0\uFE0F';
      case AlertBannerType.success:
        return '\u2705';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _backgroundColor,
        border: Border(
          left: BorderSide(color: _borderColor, width: 4),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            emoji ?? _defaultEmoji,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
