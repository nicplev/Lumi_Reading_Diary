import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Lumi Design System - Teacher Student List Item
///
/// Avatar + name + books assigned + streak indicator.
/// Per style preview: 40px avatar, 14px name, 12px subtitle, flame streak.
class TeacherStudentListItem extends StatelessWidget {
  final String name;
  final String initial;
  final Color avatarColor;
  final String subtitle;
  final int? streak;
  final VoidCallback? onTap;

  const TeacherStudentListItem({
    super.key,
    required this.name,
    required this.initial,
    this.avatarColor = const Color(0xFFFFCDD2),
    this.subtitle = '',
    this.streak,
    this.onTap,
  });

  /// Rotating palette of soft avatar colors
  static const List<Color> avatarColors = [
    Color(0xFFFFCDD2), // pink
    Color(0xFFBBDEFB), // blue
    Color(0xFFC8E6C9), // green
    Color(0xFFFFE0B2), // orange
    Color(0xFFE1BEE7), // purple
    Color(0xFFB2EBF2), // cyan
  ];

  /// Get a color based on the student name hash
  static Color colorForName(String name) {
    return avatarColors[name.hashCode.abs() % avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: AppColors.charcoal.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.charcoal,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              // Streak indicator
              if (streak != null && streak! > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '\uD83D\uDD25',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$streak',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warmOrange,
                      ),
                    ),
                  ],
                )
              else
                Text(
                  '—',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
